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

	// True when the draw path, and not the pipeline object, owns the topology, the
	// cull mode, the front face and the depth state.
	//
	// The shader cache loader and the interpreter preloader ask this as well as the
	// draw path, and the first of those can run before a device exists.
	static bool extended_dynamic_state_active()
	{
		return g_render_device && g_render_device->get_extended_dynamic_state_support();
	}

	VkPrimitiveTopology get_pipeline_topology(VkPrimitiveTopology topology, VkBool32 primitive_restart)
	{
		if (!extended_dynamic_state_active())
		{
			return topology;
		}

		// vkCmdSetPrimitiveTopology can only move inside the topology CLASS which built
		// the pipeline object. Pick one member of the class for every member of it, so
		// that the whole class shares one pipeline.
		//
		// The choice inside the class is not free. A pipeline with
		// primitiveRestartEnable set must name a strip topology or a fan topology, so
		// the restart flag decides which member represents the class.
		switch (topology)
		{
		case VK_PRIMITIVE_TOPOLOGY_LINE_LIST:
		case VK_PRIMITIVE_TOPOLOGY_LINE_STRIP:
			return primitive_restart ? VK_PRIMITIVE_TOPOLOGY_LINE_STRIP : VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST:
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP:
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN:
			return primitive_restart ? VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP : VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
		default:
			return topology;
		}
	}

	void normalize_dynamic_pipeline_state(pipeline_props& props)
	{
		if (!extended_dynamic_state_active())
		{
			return;
		}

		// Take the states which the draw path now sets out of the pipeline identity.
		// The values below are placeholders and never reach the GPU: every one of them
		// is overwritten by set_extended_dynamic_state() before the draw. They only
		// have to be the SAME placeholders every time, so that two RSX states which
		// differ in nothing else now hash to one pipeline.
		props.state.ia.topology = get_pipeline_topology(props.state.ia.topology, props.state.ia.primitiveRestartEnable);

		props.state.rs.cullMode = VK_CULL_MODE_NONE;
		props.state.rs.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;

		props.state.ds.depthTestEnable = VK_FALSE;
		props.state.ds.depthWriteEnable = VK_FALSE;
		props.state.ds.depthCompareOp = VK_COMPARE_OP_NEVER;
	}

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
		bool g_pipeline_preload_cache_hits_only_enabled = false;
		atomic_t<u32> g_pipeline_preload_cache_hit_count{};
		atomic_t<u32> g_pipeline_preload_compile_required_count{};
		thread_local bool g_pipeline_preload_cache_hit_scope_active = false;
		thread_local bool g_pipeline_preload_compile_required = false;

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

		bool pipeline_preload_cache_hits_only_requested()
		{
			char value[PROP_VALUE_MAX] = {};
			const int length = __system_property_get("debug.rpcsx.thor.vk_preload_cache_hits_only", value);
			if (length <= 0)
			{
				return false;
			}

			const std::string_view setting{value, static_cast<usz>(length)};
			return setting == "on" || setting == "1" || setting == "true";
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
			g_pipeline_preload_cache_hits_only_enabled = false;
			g_pipeline_preload_cache_hit_count.store(0);
			g_pipeline_preload_compile_required_count.store(0);
			const bool cache_hits_only_requested = pipeline_preload_cache_hits_only_requested();

			if (!driver_pipeline_cache_enabled() || g_cfg.video.disable_on_disk_shader_cache)
			{
				rsx_log.notice("Vulkan driver pipeline cache is disabled.");
				if (cache_hits_only_requested)
				{
					rsx_log.always()("Vulkan preload cache-hits-only was requested without an enabled driver cache; using normal preload.");
				}
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

			if (cache_hits_only_requested)
			{
				if (!g_render_device->get_pipeline_creation_cache_control_support())
				{
					rsx_log.always()("Vulkan preload cache-hits-only was requested but pipelineCreationCacheControl is unsupported; using normal preload.");
				}
				else if (!accepted_seed_size)
				{
					rsx_log.always()("Vulkan preload cache-hits-only was requested without a validated warm seed; using normal preload.");
				}
				else
				{
					g_pipeline_preload_cache_hits_only_enabled = true;
					rsx_log.always()("Vulkan preload cache-hits-only enabled for validated warm seed (%llu bytes).",
						static_cast<u64>(accepted_seed_size));
				}
			}
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
			if (g_pipeline_preload_cache_hits_only_enabled ||
				g_pipeline_preload_cache_hit_count.load() || g_pipeline_preload_compile_required_count.load())
			{
				rsx_log.notice("Vulkan preload cache-hits-only summary: hits=%u, deferred_misses=%u.",
					g_pipeline_preload_cache_hit_count.load(), g_pipeline_preload_compile_required_count.load());
			}
			g_pipeline_preload_cache_hits_only_enabled = false;

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

	pipeline_preload_cache_hit_scope::pipeline_preload_cache_hit_scope()
	{
#ifdef __ANDROID__
		ensure(!g_pipeline_preload_cache_hit_scope_active);
		g_pipeline_preload_compile_required = false;
		g_pipeline_preload_cache_hit_scope_active = g_pipeline_preload_cache_hits_only_enabled;
#endif
	}

	pipeline_preload_cache_hit_scope::~pipeline_preload_cache_hit_scope()
	{
#ifdef __ANDROID__
		g_pipeline_preload_cache_hit_scope_active = false;
		g_pipeline_preload_compile_required = false;
#endif
	}

	bool consume_pipeline_preload_compile_required()
	{
#ifdef __ANDROID__
		if (g_pipeline_preload_compile_required)
		{
			g_pipeline_preload_compile_required = false;
			return true;
		}
#endif
		return false;
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
					auto compiled = int_compile_graphics_pipe(job.graphics_data, job.graphics_modules, job.pipe_layout, job.inputs, {}, job.flags);
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
		VkPipeline pipeline = VK_NULL_HANDLE;
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
		VkPipeline pipeline = VK_NULL_HANDLE;
		VkGraphicsPipelineCreateInfo effective_create_info = create_info;
#ifdef __ANDROID__
		if (g_pipeline_preload_cache_hit_scope_active)
		{
			effective_create_info.flags |= VK_PIPELINE_CREATE_FAIL_ON_PIPELINE_COMPILE_REQUIRED_BIT;
		}
#endif
		const auto start = std::chrono::steady_clock::now();
		const VkResult compile_result = VK_GET_SYMBOL(vkCreateGraphicsPipelines)(
			*m_device, g_driver_pipeline_cache, 1, &effective_create_info, nullptr, &pipeline);
		const auto elapsed_us = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - start).count();
		vk::thor::rsx_auditor::record_pipeline_create(true, static_cast<u64>(elapsed_us));
#ifdef __ANDROID__
		if (compile_result == VK_PIPELINE_COMPILE_REQUIRED && g_pipeline_preload_cache_hit_scope_active)
		{
			if (pipeline != VK_NULL_HANDLE)
			{
				VK_GET_SYMBOL(vkDestroyPipeline)(*m_device, pipeline, nullptr);
			}
			g_pipeline_preload_compile_required = true;
			g_pipeline_preload_compile_required_count.fetch_add(1);
			return {};
		}
#endif
		CHECK_RESULT(compile_result);
#ifdef __ANDROID__
		if (g_pipeline_preload_cache_hit_scope_active)
		{
			g_pipeline_preload_cache_hit_count.fetch_add(1);
		}
#endif
		note_driver_pipeline_create();
		auto result = std::make_unique<vk::glsl::program>(*m_device, pipeline, pipe_layout, vs_inputs, fs_inputs);
		result->link();
		return result;
	}

	std::unique_ptr<glsl::program> pipe_compiler::int_compile_graphics_pipe(const vk::pipeline_props& create_info, VkShaderModule modules[2], VkPipelineLayout pipe_layout,
		const std::vector<glsl::program_input>& vs_inputs, const std::vector<glsl::program_input>& fs_inputs, op_flags flags)
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

		if (extended_dynamic_state_active())
		{
			dynamic_state_descriptors.push_back(VK_DYNAMIC_STATE_PRIMITIVE_TOPOLOGY_EXT);
			dynamic_state_descriptors.push_back(VK_DYNAMIC_STATE_CULL_MODE_EXT);
			dynamic_state_descriptors.push_back(VK_DYNAMIC_STATE_FRONT_FACE_EXT);
			dynamic_state_descriptors.push_back(VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE_EXT);
			dynamic_state_descriptors.push_back(VK_DYNAMIC_STATE_DEPTH_WRITE_ENABLE_EXT);
			dynamic_state_descriptors.push_back(VK_DYNAMIC_STATE_DEPTH_COMPARE_OP_EXT);
		}

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

		// Flat shading takes the color from the LAST vertex, which is the RSX convention.
		// VK_EXT_provoking_vertex gives that; the caller sets the flag only when the device
		// reports the feature, so the ensure() below cannot fire on a device without it.
		VkPipelineRasterizationStateCreateInfo rs = create_info.state.rs;
		VkPipelineRasterizationProvokingVertexStateCreateInfoEXT provoking_vertex_state{};
		if (flags & USE_LAST_PROVOKING_VERTEX)
		{
			ensure(m_device->get_provoking_vertex_last_support());
			provoking_vertex_state.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_PROVOKING_VERTEX_STATE_CREATE_INFO_EXT;
			provoking_vertex_state.pNext = rs.pNext;
			provoking_vertex_state.provokingVertexMode = VK_PROVOKING_VERTEX_MODE_LAST_VERTEX_EXT;
			rs.pNext = &provoking_vertex_state;
		}

		VkGraphicsPipelineCreateInfo info = {};
		info.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
		info.pVertexInputState = &vi;
		info.pInputAssemblyState = &create_info.state.ia;
		info.pRasterizationState = &rs;
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
		ensure(!(flags & COMPILE_DEFERRED));
		return int_compile_graphics_pipe(create_info, pipe_layout, vs_inputs, fs_inputs);
	}

	std::unique_ptr<glsl::program> pipe_compiler::compile(
		const vk::pipeline_props& create_info,
		VkShaderModule module_handles[2],
		VkPipelineLayout pipe_layout,
		op_flags flags, callback_t callback,
		const std::vector<glsl::program_input>& vs_inputs, const std::vector<glsl::program_input>& fs_inputs)
	{
		// Test the bit. flags now also carries USE_LAST_PROVOKING_VERTEX, so an equality
		// comparison against COMPILE_INLINE would send an inline compile to the queue.
		if (!(flags & COMPILE_DEFERRED))
		{
			return int_compile_graphics_pipe(create_info, module_handles, pipe_layout, vs_inputs, fs_inputs, flags);
		}

		m_work_queue.push(create_info, pipe_layout, module_handles, vs_inputs, fs_inputs, callback, flags);
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
