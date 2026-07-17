#include "stdafx.h"
#include "VKPipelineCompiler.h"
#include "VKRenderPass.h"
#include "vkutils/device.h"
#include "vkutils/thor_rsx_auditor.h"
#include "Emu/cache_utils.hpp"
#include "util/File.h"
#include "util/Thread.h"

#include "util/sysinfo.hpp"

#include <chrono>
#include <cstring>
#include <mutex>
#include <string_view>

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace vk
{
	// Global list of worker threads
	std::unique_ptr<named_thread_group<pipe_compiler>> g_pipe_compilers;
	int g_num_pipe_compilers = 0;
	atomic_t<int> g_compiler_index{};

	namespace
	{
		VkPipelineCache g_driver_pipeline_cache = VK_NULL_HANDLE;

#ifdef __ANDROID__
		constexpr usz driver_pipeline_cache_header_size = 32;
		constexpr usz driver_pipeline_cache_max_size = 64 * 1024 * 1024;
		std::string g_driver_pipeline_cache_path;
		atomic_t<u32> g_driver_pipeline_create_count{};
		u32 g_driver_pipeline_first_checkpoint = 32;
		std::mutex g_driver_pipeline_checkpoint_mutex;

		u32 read_pipeline_cache_u32(const u8* data)
		{
			return static_cast<u32>(data[0]) |
				(static_cast<u32>(data[1]) << 8) |
				(static_cast<u32>(data[2]) << 16) |
				(static_cast<u32>(data[3]) << 24);
		}

		bool driver_pipeline_cache_enabled()
		{
			char value[PROP_VALUE_MAX] = {};
			const int length = __system_property_get("debug.rpcsx.thor.vk_pipeline_cache", value);
			if (length <= 0)
			{
				return true;
			}

			const std::string_view setting{value, static_cast<usz>(length)};
			return setting != "off" && setting != "0" && setting != "false";
		}

		bool validate_driver_pipeline_cache(const void* cache_data, usz cache_size, const VkPhysicalDeviceProperties& properties)
		{
			if (!cache_data || cache_size < driver_pipeline_cache_header_size || cache_size > driver_pipeline_cache_max_size)
			{
				return false;
			}

			const auto* data = static_cast<const u8*>(cache_data);
			return read_pipeline_cache_u32(data) == driver_pipeline_cache_header_size &&
				read_pipeline_cache_u32(data + 4) == VK_PIPELINE_CACHE_HEADER_VERSION_ONE &&
				read_pipeline_cache_u32(data + 8) == properties.vendorID &&
				read_pipeline_cache_u32(data + 12) == properties.deviceID &&
				std::memcmp(data + 16, properties.pipelineCacheUUID, VK_UUID_SIZE) == 0;
		}

		std::vector<u8> load_driver_pipeline_cache(const VkPhysicalDeviceProperties& properties)
		{
			fs::file cache_file{g_driver_pipeline_cache_path, fs::read + fs::isfile};
			if (!cache_file)
			{
				return {};
			}

			const u64 cache_size = cache_file.size();
			if (cache_size < driver_pipeline_cache_header_size || cache_size > driver_pipeline_cache_max_size)
			{
				rsx_log.warning("Ignoring Vulkan driver pipeline cache with invalid size %llu.", cache_size);
				return {};
			}

			std::vector<u8> cache_data(static_cast<usz>(cache_size));
			if (cache_file.read(cache_data.data(), cache_data.size()) != cache_data.size() ||
				!validate_driver_pipeline_cache(cache_data.data(), cache_data.size(), properties))
			{
				rsx_log.warning("Ignoring Vulkan driver pipeline cache that does not match the current GPU/driver.");
				return {};
			}

			return cache_data;
		}

		void save_driver_pipeline_cache(bool final_checkpoint)
		{
			if (g_driver_pipeline_cache == VK_NULL_HANDLE || g_driver_pipeline_cache_path.empty())
			{
				return;
			}

			std::unique_lock lock(g_driver_pipeline_checkpoint_mutex, std::defer_lock);
			if (final_checkpoint)
			{
				lock.lock();
			}
			else if (!lock.try_lock())
			{
				return;
			}

			std::vector<u8> cache_data;
			bool cache_ready = false;
			for (u32 attempt = 0; attempt < 3; attempt++)
			{
				size_t cache_size = 0;
				VkResult result = VK_GET_SYMBOL(vkGetPipelineCacheData)(
					*g_render_device, g_driver_pipeline_cache, &cache_size, nullptr);
				if (result != VK_SUCCESS || cache_size < driver_pipeline_cache_header_size ||
					cache_size > driver_pipeline_cache_max_size)
				{
					rsx_log.warning("Could not size Vulkan driver pipeline cache (result=0x%x, size=%llu).",
						static_cast<u32>(result), static_cast<u64>(cache_size));
					return;
				}

				cache_data.resize(cache_size);
				size_t written_size = cache_size;
				result = VK_GET_SYMBOL(vkGetPipelineCacheData)(
					*g_render_device, g_driver_pipeline_cache, &written_size, cache_data.data());
				if (result == VK_SUCCESS)
				{
					cache_data.resize(written_size);
					cache_ready = true;
					break;
				}

				if (result != VK_INCOMPLETE)
				{
					rsx_log.warning("Could not serialize Vulkan driver pipeline cache (result=0x%x).",
						static_cast<u32>(result));
					return;
				}
			}

			const auto& properties = g_render_device->gpu().get_properties();
			if (!cache_ready ||
				!validate_driver_pipeline_cache(cache_data.data(), cache_data.size(), properties))
			{
				rsx_log.warning("Vulkan driver pipeline cache serialization stayed incomplete or produced an invalid header.");
				return;
			}

			if (!fs::write_pending_file(g_driver_pipeline_cache_path, cache_data.data(), cache_data.size()))
			{
				rsx_log.warning("Could not atomically save Vulkan driver pipeline cache.");
				return;
			}

			rsx_log.notice("Saved Vulkan driver pipeline cache (%llu bytes, pipelines=%u%s).",
				static_cast<u64>(cache_data.size()), g_driver_pipeline_create_count.load(),
				final_checkpoint ? ", final" : "");
		}

		void initialize_driver_pipeline_cache()
		{
			g_driver_pipeline_create_count.store(0);
			g_driver_pipeline_first_checkpoint = 32;
			g_driver_pipeline_cache_path.clear();

			if (!driver_pipeline_cache_enabled() || g_cfg.video.disable_on_disk_shader_cache)
			{
				rsx_log.notice("Vulkan driver pipeline cache is disabled.");
				return;
			}

			std::string cache_root = rpcs3::cache::get_ppu_cache();
			if (cache_root.empty())
			{
				rsx_log.warning("Vulkan driver pipeline cache has no title cache path.");
				return;
			}

			cache_root += "shaders_cache/vulkan/";
			if (!fs::create_path(cache_root))
			{
				rsx_log.warning("Could not create Vulkan driver pipeline cache directory.");
				return;
			}

			g_driver_pipeline_cache_path = cache_root + "driver_pipeline_cache.bin";
			const auto& properties = g_render_device->gpu().get_properties();
			const std::vector<u8> initial_data = load_driver_pipeline_cache(properties);

			VkPipelineCacheCreateInfo create_info{VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO};
			create_info.initialDataSize = initial_data.size();
			create_info.pInitialData = initial_data.empty() ? nullptr : initial_data.data();
			usz accepted_seed_size = initial_data.size();

			VkResult result = VK_GET_SYMBOL(vkCreatePipelineCache)(
				*g_render_device, &create_info, nullptr, &g_driver_pipeline_cache);
			if (result != VK_SUCCESS && !initial_data.empty())
			{
				rsx_log.warning("Vulkan driver rejected saved pipeline cache (result=0x%x); retrying empty.",
					static_cast<u32>(result));
				create_info.initialDataSize = 0;
				create_info.pInitialData = nullptr;
				accepted_seed_size = 0;
				result = VK_GET_SYMBOL(vkCreatePipelineCache)(
					*g_render_device, &create_info, nullptr, &g_driver_pipeline_cache);
			}

			if (result != VK_SUCCESS)
			{
				g_driver_pipeline_cache = VK_NULL_HANDLE;
				rsx_log.warning("Could not create Vulkan driver pipeline cache (result=0x%x).",
					static_cast<u32>(result));
				return;
			}

			// A validated warm seed already contains the early pipeline states. Avoid
			// serializing and rewriting that same multi-megabyte blob at the early
			// session thresholds. The Android bounded startup path creates 256 pipelines,
			// so its first warm checkpoint must stay beyond that hot path. Cold caches
			// retain crash-safe 32/64/128/... checkpoints, and final shutdown still saves
			// any warm progress below the first periodic checkpoint.
#ifdef __ANDROID__
			g_driver_pipeline_first_checkpoint = accepted_seed_size ? 512u : 32u;
#else
			g_driver_pipeline_first_checkpoint = accepted_seed_size ? 256u : 32u;
#endif
			rsx_log.notice("Created Vulkan driver pipeline cache (seed=%llu bytes).",
				static_cast<u64>(accepted_seed_size));
			rsx_log.notice("Vulkan driver pipeline cache first checkpoint: %u pipelines.",
				g_driver_pipeline_first_checkpoint);
		}

		void note_driver_pipeline_create()
		{
			const u32 create_count = g_driver_pipeline_create_count.fetch_add(1) + 1;
			if (create_count >= g_driver_pipeline_first_checkpoint && (create_count & (create_count - 1)) == 0)
			{
				save_driver_pipeline_cache(false);
			}
		}

		void destroy_driver_pipeline_cache()
		{
			if (g_driver_pipeline_cache == VK_NULL_HANDLE)
			{
				return;
			}

			save_driver_pipeline_cache(true);
			VK_GET_SYMBOL(vkDestroyPipelineCache)(*g_render_device, g_driver_pipeline_cache, nullptr);
			g_driver_pipeline_cache = VK_NULL_HANDLE;
			g_driver_pipeline_first_checkpoint = 32;
			g_driver_pipeline_cache_path.clear();
		}
#else
		void initialize_driver_pipeline_cache()
		{
		}

		void note_driver_pipeline_create()
		{
		}

		void destroy_driver_pipeline_cache()
		{
		}
#endif
	}

	pipe_compiler::pipe_compiler()
	{
		// TODO: Initialize workqueue
	}

	pipe_compiler::~pipe_compiler()
	{
		// TODO: Destroy and do cleanup
	}

	void pipe_compiler::initialize(const vk::render_device* pdev)
	{
		m_device = pdev;
	}

	void pipe_compiler::operator()()
	{
		while (thread_ctrl::state() != thread_state::aborting)
		{
			for (auto&& job : m_work_queue.pop_all())
			{
				if (job.is_graphics_job)
				{
					auto compiled = int_compile_graphics_pipe(job.graphics_data, job.graphics_modules, job.pipe_layout, job.inputs, {});
					job.callback_func(compiled);
				}
				else
				{
					auto compiled = int_compile_compute_pipe(job.compute_data, job.pipe_layout);
					job.callback_func(compiled);
				}
			}

			thread_ctrl::wait_on(m_work_queue);
		}
	}

	std::unique_ptr<glsl::program> pipe_compiler::int_compile_compute_pipe(const VkComputePipelineCreateInfo& create_info, VkPipelineLayout pipe_layout)
	{
		VkPipeline pipeline;
		const auto start = std::chrono::steady_clock::now();
		const VkResult compile_result = VK_GET_SYMBOL(vkCreateComputePipelines)(
			*g_render_device, g_driver_pipeline_cache, 1, &create_info, nullptr, &pipeline);
		const auto elapsed_us = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - start).count();
		vk::thor::rsx_auditor::record_pipeline_create(false, static_cast<u64>(elapsed_us));
		CHECK_RESULT(compile_result);
		note_driver_pipeline_create();
		return std::make_unique<vk::glsl::program>(*m_device, pipeline, pipe_layout);
	}

	std::unique_ptr<glsl::program> pipe_compiler::int_compile_graphics_pipe(const VkGraphicsPipelineCreateInfo& create_info, VkPipelineLayout pipe_layout,
		const std::vector<glsl::program_input>& vs_inputs, const std::vector<glsl::program_input>& fs_inputs)
	{
		VkPipeline pipeline;
		const auto start = std::chrono::steady_clock::now();
		const VkResult compile_result = VK_GET_SYMBOL(vkCreateGraphicsPipelines)(
			*m_device, g_driver_pipeline_cache, 1, &create_info, nullptr, &pipeline);
		const auto elapsed_us = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - start).count();
		vk::thor::rsx_auditor::record_pipeline_create(true, static_cast<u64>(elapsed_us));
		CHECK_RESULT(compile_result);
		note_driver_pipeline_create();
		auto result = std::make_unique<vk::glsl::program>(*m_device, pipeline, pipe_layout, vs_inputs, fs_inputs);
		result->link();
		return result;
	}

	std::unique_ptr<glsl::program> pipe_compiler::int_compile_graphics_pipe(const vk::pipeline_props& create_info, VkShaderModule modules[2], VkPipelineLayout pipe_layout,
		const std::vector<glsl::program_input>& vs_inputs, const std::vector<glsl::program_input>& fs_inputs)
	{
		VkPipelineShaderStageCreateInfo shader_stages[2] = {};
		shader_stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
		shader_stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
		shader_stages[0].module = modules[0];
		shader_stages[0].pName = "main";

		shader_stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
		shader_stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
		shader_stages[1].module = modules[1];
		shader_stages[1].pName = "main";

		std::vector<VkDynamicState> dynamic_state_descriptors;
		dynamic_state_descriptors.push_back(VK_DYNAMIC_STATE_VIEWPORT);
		dynamic_state_descriptors.push_back(VK_DYNAMIC_STATE_SCISSOR);
		dynamic_state_descriptors.push_back(VK_DYNAMIC_STATE_LINE_WIDTH);
		dynamic_state_descriptors.push_back(VK_DYNAMIC_STATE_BLEND_CONSTANTS);
		dynamic_state_descriptors.push_back(VK_DYNAMIC_STATE_STENCIL_COMPARE_MASK);
		dynamic_state_descriptors.push_back(VK_DYNAMIC_STATE_STENCIL_WRITE_MASK);
		dynamic_state_descriptors.push_back(VK_DYNAMIC_STATE_STENCIL_REFERENCE);
		dynamic_state_descriptors.push_back(VK_DYNAMIC_STATE_DEPTH_BIAS);

		auto pdss = &create_info.state.ds;
		VkPipelineDepthStencilStateCreateInfo ds2;
		if (g_render_device->get_depth_bounds_support()) [[likely]]
		{
			dynamic_state_descriptors.push_back(VK_DYNAMIC_STATE_DEPTH_BOUNDS);
		}
		else if (pdss->depthBoundsTestEnable)
		{
			rsx_log.warning("Depth bounds test is enabled in the pipeline object but not supported by the current driver.");

			ds2 = *pdss;
			pdss = &ds2;
			ds2.depthBoundsTestEnable = VK_FALSE;
		}

		VkPipelineDynamicStateCreateInfo dynamic_state_info = {};
		dynamic_state_info.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
		dynamic_state_info.pDynamicStates = dynamic_state_descriptors.data();
		dynamic_state_info.dynamicStateCount = ::size32(dynamic_state_descriptors);

		VkPipelineVertexInputStateCreateInfo vi = {VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};

		VkPipelineViewportStateCreateInfo vp = {};
		vp.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
		vp.viewportCount = 1;
		vp.scissorCount = 1;

		auto pmss = &create_info.state.ms;
		VkPipelineMultisampleStateCreateInfo ms2;
		ensure(pmss->rasterizationSamples == VkSampleCountFlagBits((create_info.renderpass_key >> 16) & 0xF)); // "Multisample state mismatch!"

		if (pmss->rasterizationSamples != VK_SAMPLE_COUNT_1_BIT || pmss->sampleShadingEnable) [[unlikely]]
		{
			ms2 = *pmss;
			pmss = &ms2;

			if (ms2.rasterizationSamples != VK_SAMPLE_COUNT_1_BIT)
			{
				// Update the sample mask pointer
				ms2.pSampleMask = &create_info.state.temp_storage.msaa_sample_mask;
			}

			if (g_cfg.video.antialiasing_level == msaa_level::none && ms2.sampleShadingEnable)
			{
				// Do not compile with MSAA enabled if multisampling is disabled
				rsx_log.warning("MSAA is disabled globally but a shader with multi-sampling enabled was submitted for compilation.");
				ms2.sampleShadingEnable = VK_FALSE;
			}
		}

		// Rebase pointers from pipeline structure in case it is moved/copied
		VkPipelineColorBlendStateCreateInfo cs = create_info.state.cs;
		cs.pAttachments = create_info.state.att_state;

		VkGraphicsPipelineCreateInfo info = {};
		info.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
		info.pVertexInputState = &vi;
		info.pInputAssemblyState = &create_info.state.ia;
		info.pRasterizationState = &create_info.state.rs;
		info.pColorBlendState = &cs;
		info.pMultisampleState = pmss;
		info.pViewportState = &vp;
		info.pDepthStencilState = pdss;
		info.stageCount = 2;
		info.pStages = shader_stages;
		info.pDynamicState = &dynamic_state_info;
		info.layout = pipe_layout;
		info.basePipelineIndex = -1;
		info.basePipelineHandle = VK_NULL_HANDLE;
		info.renderPass = vk::get_renderpass(*m_device, create_info.renderpass_key);

		return int_compile_graphics_pipe(info, pipe_layout, vs_inputs, fs_inputs);
	}

	std::unique_ptr<glsl::program> pipe_compiler::compile(
		const VkComputePipelineCreateInfo& create_info,
		VkPipelineLayout pipe_layout,
		op_flags flags, callback_t callback)
	{
		if (flags == COMPILE_INLINE)
		{
			return int_compile_compute_pipe(create_info, pipe_layout);
		}

		m_work_queue.push(create_info, pipe_layout, callback);
		return {};
	}

	std::unique_ptr<glsl::program> pipe_compiler::compile(
		const VkGraphicsPipelineCreateInfo& create_info,
		VkPipelineLayout pipe_layout,
		op_flags flags, callback_t /*callback*/,
		const std::vector<glsl::program_input>& vs_inputs, const std::vector<glsl::program_input>& fs_inputs)
	{
		// It is very inefficient to defer this as all pointers need to be saved
		ensure(flags == COMPILE_INLINE);
		return int_compile_graphics_pipe(create_info, pipe_layout, vs_inputs, fs_inputs);
	}

	std::unique_ptr<glsl::program> pipe_compiler::compile(
		const vk::pipeline_props& create_info,
		VkShaderModule module_handles[2],
		VkPipelineLayout pipe_layout,
		op_flags flags, callback_t callback,
		const std::vector<glsl::program_input>& vs_inputs, const std::vector<glsl::program_input>& fs_inputs)
	{
		if (flags == COMPILE_INLINE)
		{
			return int_compile_graphics_pipe(create_info, module_handles, pipe_layout, vs_inputs, fs_inputs);
		}

		m_work_queue.push(create_info, pipe_layout, module_handles, vs_inputs, fs_inputs, callback);
		return {};
	}

	void initialize_pipe_compiler(int num_worker_threads)
	{
		if (num_worker_threads == 0)
		{
			// Select optimal number of compiler threads
			const auto hw_threads = utils::get_thread_count();
			if (hw_threads > 12)
			{
				num_worker_threads = 6;
			}
			else if (hw_threads > 8)
			{
				num_worker_threads = 4;
			}
			else if (hw_threads == 8)
			{
				num_worker_threads = 2;
			}
			else
			{
				num_worker_threads = 1;
			}
		}

		ensure(num_worker_threads >= 1);
		ensure(g_render_device); // "Cannot initialize pipe compiler before creating a logical device"
		initialize_driver_pipeline_cache();

		// Create the thread pool
		g_pipe_compilers = std::make_unique<named_thread_group<pipe_compiler>>("RSX.W", num_worker_threads);
		g_num_pipe_compilers = num_worker_threads;

		// Initialize the workers. At least one inline compiler shall exist (doesn't actually run)
		for (pipe_compiler& compiler : *g_pipe_compilers.get())
		{
			compiler.initialize(g_render_device);
		}
	}

	void destroy_pipe_compiler()
	{
		g_pipe_compilers.reset();
		destroy_driver_pipeline_cache();
	}

	pipe_compiler* get_pipe_compiler()
	{
		ensure(g_pipe_compilers);
		int thread_index = g_compiler_index++;

		return g_pipe_compilers.get()->begin() + (thread_index % g_num_pipe_compilers);
	}
} // namespace vk
