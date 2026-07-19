#include "stdafx.h"

#include "VKResolveHelper.h"
#include "VKRenderPass.h"
#include "VKRenderTargets.h"

namespace
{
	const char* get_format_prefix(VkFormat format)
	{
		switch (format)
		{
		case VK_FORMAT_R5G6B5_UNORM_PACK16:
			return "r16";
		case VK_FORMAT_R8G8B8A8_UNORM:
		case VK_FORMAT_B8G8R8A8_UNORM:
			return "rgba8";
		case VK_FORMAT_R16G16B16A16_SFLOAT:
			return "rgba16f";
		case VK_FORMAT_R32G32B32A32_SFLOAT:
			return "rgba32f";
		case VK_FORMAT_A1R5G5B5_UNORM_PACK16:
			return "r16";
		case VK_FORMAT_R8_UNORM:
			return "r8";
		case VK_FORMAT_R8G8_UNORM:
			return "rg8";
		case VK_FORMAT_R32_SFLOAT:
			return "r32f";
		default:
			fmt::throw_exception("Unhandled VkFormat 0x%x", u32(format));
		}
	}
} // namespace

namespace vk
{
#if !defined(ANDROID) || defined(RPCSX_THOR_RSX_EXPERIMENTS)
	struct cs_resolve_blit_task : compute_task
	{
		vk::viewable_image* multisampled = nullptr;
		vk::viewable_image* dest = nullptr;
		u32 cs_wave_x = 1;
		u32 cs_wave_y = 1;
		s32 params[8]{};

		cs_resolve_blit_task(const std::string& format_prefix, bool bgra_swap = false)
		{
			ssbo_count = 0;
			use_push_constants = true;
			push_constants_size = sizeof(params);
			build(format_prefix, bgra_swap);
		}

		std::vector<std::pair<VkDescriptorType, u8>> get_descriptor_layout() override
		{
			return {{VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 2}};
		}

		void declare_inputs() override
		{
			std::vector<vk::glsl::program_input> inputs =
				{
					{::glsl::program_domain::glsl_compute_program,
						vk::glsl::program_input_type::input_type_texture,
						{}, {},
						0,
						"multisampled"},
					{::glsl::program_domain::glsl_compute_program,
						vk::glsl::program_input_type::input_type_texture,
						{}, {},
						1,
						"dest"}};

			m_program->load_uniforms(inputs);
		}

		void bind_resources() override
		{
			auto msaa_view = multisampled->get_view(rsx::default_remap_vector.with_encoding(VK_REMAP_VIEW_MULTISAMPLED));
			auto dest_view = dest->get_view(rsx::default_remap_vector.with_encoding(VK_REMAP_IDENTITY));
			m_program->bind_uniform({VK_NULL_HANDLE, msaa_view->value, multisampled->current_layout}, "multisampled", VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, m_descriptor_set);
			m_program->bind_uniform({VK_NULL_HANDLE, dest_view->value, dest->current_layout}, "dest", VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, m_descriptor_set);
		}

		void build(const std::string& format_prefix, bool bgra_swap)
		{
			create();

			switch (optimal_group_size)
			{
			default:
			case 64:
				cs_wave_x = 8;
				cs_wave_y = 8;
				break;
			case 32:
				cs_wave_x = 8;
				cs_wave_y = 4;
				break;
			}

			m_src = R"(
#version 430

layout(local_size_x=%WORKGROUP_SIZE_X, local_size_y=%WORKGROUP_SIZE_Y, local_size_z=1) in;

#ifdef VULKAN
layout(set=0, binding=0, %IMAGE_FORMAT) uniform readonly restrict image2DMS multisampled;
layout(set=0, binding=1) uniform writeonly restrict image2D dest;
#else
layout(binding=0, %IMAGE_FORMAT) uniform readonly restrict image2DMS multisampled;
layout(binding=1) uniform writeonly restrict image2D dest;
#endif

layout(push_constant) uniform ubo
{
	ivec4 rect0;
	ivec4 rect1;
};

#if %BGRA_SWAP
#define shuffle(x) (x.bgra)
#else
#define shuffle(x) (x)
#endif

void main()
{
	ivec2 local = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = rect1.xy;
	ivec2 sample_count = rect1.zw;
	if (any(greaterThanEqual(local, size))) return;

	ivec2 resolve_coords = rect0.xy + local;
	ivec2 aa_coords = resolve_coords / sample_count;
	ivec2 sample_loc = ivec2(resolve_coords % sample_count);
	int sample_index = sample_loc.x + (sample_loc.y * sample_count.y);

	vec4 aa_sample = imageLoad(multisampled, aa_coords, sample_index);
	imageStore(dest, rect0.zw + local, shuffle(aa_sample));
}
)";

			const std::pair<std::string_view, std::string> syntax_replace[] =
				{
					{"%WORKGROUP_SIZE_X", std::to_string(cs_wave_x)},
					{"%WORKGROUP_SIZE_Y", std::to_string(cs_wave_y)},
					{"%IMAGE_FORMAT", format_prefix},
					{"%BGRA_SWAP", bgra_swap ? "1" : "0"}};

			m_src = fmt::replace_all(m_src, syntax_replace);
		}

		void run(const vk::command_buffer& cmd, vk::viewable_image* msaa_image, vk::viewable_image* dest_image, areai src_area, areai dst_area, u32 samples_x, u32 samples_y)
		{
			ensure(msaa_image->samples() > 1);
			ensure(dest_image->samples() == 1);
			ensure(src_area.width() == dst_area.width());
			ensure(src_area.height() == dst_area.height());

			multisampled = msaa_image;
			dest = dest_image;

			params[0] = src_area.x1;
			params[1] = src_area.y1;
			params[2] = dst_area.x1;
			params[3] = dst_area.y1;
			params[4] = src_area.width();
			params[5] = src_area.height();
			params[6] = static_cast<s32>(samples_x);
			params[7] = static_cast<s32>(samples_y);

			VK_GET_SYMBOL(vkCmdPushConstants)(cmd, m_pipeline_layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, push_constants_size, params);

			const u32 invocations_x = rx::alignUp(static_cast<u32>(src_area.width()), cs_wave_x) / cs_wave_x;
			const u32 invocations_y = rx::alignUp(static_cast<u32>(src_area.height()), cs_wave_y) / cs_wave_y;

			compute_task::run(cmd, invocations_x, invocations_y, 1);
		}
	};
#endif

	std::unordered_map<VkFormat, std::unique_ptr<vk::cs_resolve_task>> g_resolve_helpers;
	std::unordered_map<VkFormat, std::unique_ptr<vk::cs_unresolve_task>> g_unresolve_helpers;
#if !defined(ANDROID) || defined(RPCSX_THOR_RSX_EXPERIMENTS)
	std::unordered_map<VkFormat, std::unique_ptr<vk::cs_resolve_blit_task>> g_resolve_blit_helpers;
	std::unordered_map<u64, std::unique_ptr<vk::viewable_image>> g_resolve_blit_scratch_images;
#endif
	std::unique_ptr<vk::depthonly_resolve> g_depth_resolver;
	std::unique_ptr<vk::depthonly_unresolve> g_depth_unresolver;
	std::unique_ptr<vk::stencilonly_resolve> g_stencil_resolver;
	std::unique_ptr<vk::stencilonly_unresolve> g_stencil_unresolver;
	std::unique_ptr<vk::depthstencil_resolve_EXT> g_depthstencil_resolver;
	std::unique_ptr<vk::depthstencil_unresolve_EXT> g_depthstencil_unresolver;

	template <typename T, typename... Args>
	void initialize_pass(std::unique_ptr<T>& ptr, vk::render_device& dev, Args&&... extras)
	{
		if (!ptr)
		{
			ptr = std::make_unique<T>(std::forward<Args>(extras)...);
			ptr->create(dev);
		}
	}

	void resolve_image(vk::command_buffer& cmd, vk::viewable_image* dst, vk::viewable_image* src)
	{
		if (src->aspect() == VK_IMAGE_ASPECT_COLOR_BIT)
		{
			auto& job = g_resolve_helpers[src->format()];

			if (!job)
			{
				const char* format_prefix = get_format_prefix(src->format());
				bool require_bgra_swap = false;

				if (vk::get_chip_family() == vk::chip_class::NV_kepler &&
					src->format() == VK_FORMAT_B8G8R8A8_UNORM)
				{
					// Workaround for NVIDIA kepler's broken image_load_store
					require_bgra_swap = true;
				}

				job.reset(new vk::cs_resolve_task(format_prefix, require_bgra_swap));
			}

			job->run(cmd, src, dst);
		}
		else
		{
			std::vector<vk::image*> surface = {dst};
			auto& dev = cmd.get_command_pool().get_owner();

			const auto key = vk::get_renderpass_key(surface);
			auto renderpass = vk::get_renderpass(dev, key);

			if (src->aspect() & VK_IMAGE_ASPECT_STENCIL_BIT)
			{
				if (dev.get_shader_stencil_export_support())
				{
					initialize_pass(g_depthstencil_resolver, dev);
					g_depthstencil_resolver->run(cmd, src, dst, renderpass);
				}
				else
				{
					initialize_pass(g_depth_resolver, dev);
					g_depth_resolver->run(cmd, src, dst, renderpass);

					// Chance for optimization here: If the stencil buffer was not used, simply perform a clear operation
					const auto stencil_init_flags = vk::as_rtt(src)->stencil_init_flags;
					if (stencil_init_flags & 0xFF00)
					{
						initialize_pass(g_stencil_resolver, dev);
						g_stencil_resolver->run(cmd, src, dst, renderpass);
					}
					else
					{
						VkClearDepthStencilValue clear{1.f, stencil_init_flags & 0xFF};
						VkImageSubresourceRange range{VK_IMAGE_ASPECT_STENCIL_BIT, 0, 1, 0, 1};

						dst->push_layout(cmd, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
						VK_GET_SYMBOL(vkCmdClearDepthStencilImage)(cmd, dst->value, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &clear, 1, &range);
						dst->pop_layout(cmd);
					}
				}
			}
			else
			{
				initialize_pass(g_depth_resolver, dev);
				g_depth_resolver->run(cmd, src, dst, renderpass);
			}
		}
	}

#if !defined(ANDROID) || defined(RPCSX_THOR_RSX_EXPERIMENTS)
	bool resolve_blit_image(vk::command_buffer& cmd, vk::render_target* src, vk::image* dst, areai src_area, areai dst_area)
	{
		if (!src || !dst)
		{
			return false;
		}

		auto dst_viewable = dynamic_cast<vk::viewable_image*>(dst);
		if (!dst_viewable)
		{
			return false;
		}

		if (src->aspect() != VK_IMAGE_ASPECT_COLOR_BIT || dst->aspect() != VK_IMAGE_ASPECT_COLOR_BIT)
		{
			return false;
		}

		if (src->samples() <= 1 || dst->samples() != 1)
		{
			return false;
		}

		if (!(dst->info.usage & VK_IMAGE_USAGE_STORAGE_BIT))
		{
			return false;
		}

		if (src->format() != dst->format())
		{
			return false;
		}

		if (src_area.width() != dst_area.width() || src_area.height() != dst_area.height())
		{
			return false;
		}

		if (src_area.x1 < 0 || src_area.y1 < 0 || dst_area.x1 < 0 || dst_area.y1 < 0 ||
			src_area.x2 > static_cast<s32>(src->get_surface_width<rsx::surface_metrics::samples>()) ||
			src_area.y2 > static_cast<s32>(src->get_surface_height<rsx::surface_metrics::samples>()) ||
			dst_area.x2 > static_cast<s32>(dst->width()) ||
			dst_area.y2 > static_cast<s32>(dst->height()))
		{
			return false;
		}

		auto& job = g_resolve_blit_helpers[src->format()];
		if (!job)
		{
			const char* format_prefix = get_format_prefix(src->format());
			bool require_bgra_swap = false;

			if (vk::get_chip_family() == vk::chip_class::NV_kepler &&
				src->format() == VK_FORMAT_B8G8R8A8_UNORM)
			{
				require_bgra_swap = true;
			}

			job.reset(new vk::cs_resolve_blit_task(format_prefix, require_bgra_swap));
		}

		const VkImageSubresourceRange range = {src->aspect(), 0, 1, 0, 1};
		const VkImageLayout src_initial_layout = src->current_layout;

		vk::insert_image_memory_barrier(
			cmd, src->value,
			src->current_layout,
			VK_IMAGE_LAYOUT_GENERAL,
			VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
			VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
			VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
			VK_ACCESS_SHADER_READ_BIT,
			range);

		src->current_layout = VK_IMAGE_LAYOUT_GENERAL;
		dst_viewable->change_layout(cmd, VK_IMAGE_LAYOUT_GENERAL);

		job->run(cmd, src, dst_viewable, src_area, dst_area, src->samples_x, src->samples_y);

		vk::insert_image_memory_barrier(
			cmd, src->value,
			VK_IMAGE_LAYOUT_GENERAL,
			src_initial_layout,
			VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
			VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
			VK_ACCESS_SHADER_READ_BIT,
			VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
			range);

		const VkImageLayout dst_written_layout = dst->current_layout;
		vk::insert_image_memory_barrier(
			cmd, dst->value,
			dst_written_layout,
			VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
			VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
			VK_PIPELINE_STAGE_VERTEX_SHADER_BIT | VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
			VK_ACCESS_SHADER_WRITE_BIT,
			VK_ACCESS_SHADER_READ_BIT,
			{dst->aspect(), 0, 1, 0, 1});

		src->current_layout = src_initial_layout;
		dst->current_layout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
		return true;
	}

	bool resolve_blit_image_to_scratch(vk::command_buffer& cmd, vk::render_target* src, vk::image* dst_reference, areai src_area, areai dst_area)
	{
		if (!src || !dst_reference)
		{
			return false;
		}

		if (src->aspect() != VK_IMAGE_ASPECT_COLOR_BIT || dst_reference->aspect() != VK_IMAGE_ASPECT_COLOR_BIT)
		{
			return false;
		}

		if (src->samples() <= 1 || src->format() != dst_reference->format())
		{
			return false;
		}

		if (src_area.width() != dst_area.width() || src_area.height() != dst_area.height())
		{
			return false;
		}

		const u32 width = dst_reference->width();
		const u32 height = dst_reference->height();
		if (dst_area.x1 < 0 || dst_area.y1 < 0 ||
			dst_area.x2 > static_cast<s32>(width) ||
			dst_area.y2 > static_cast<s32>(height))
		{
			return false;
		}

		const u64 key =
			(static_cast<u64>(dst_reference->format()) << 32) ^
			(static_cast<u64>(width) << 16) ^
			static_cast<u64>(height);

		auto& scratch = g_resolve_blit_scratch_images[key];
		if (!scratch || scratch->width() != width || scratch->height() != height || scratch->format() != dst_reference->format())
		{
			auto& dev = cmd.get_command_pool().get_owner();
			scratch = std::make_unique<vk::viewable_image>(
				dev,
				dev.get_memory_mapping().device_local,
				VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
				VK_IMAGE_TYPE_2D,
				dst_reference->format(),
				width,
				height,
				1,
				1,
				1,
				VK_SAMPLE_COUNT_1_BIT,
				VK_IMAGE_LAYOUT_UNDEFINED,
				VK_IMAGE_TILING_OPTIMAL,
				VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_STORAGE_BIT,
				VK_IMAGE_CREATE_ALLOW_NULL_RPCS3,
				VMM_ALLOCATION_POOL_SCRATCH,
				dst_reference->format_class());
		}

		return scratch && scratch->value && resolve_blit_image(cmd, src, scratch.get(), src_area, dst_area);
	}
#endif

	void unresolve_image(vk::command_buffer& cmd, vk::viewable_image* dst, vk::viewable_image* src)
	{
		if (src->aspect() == VK_IMAGE_ASPECT_COLOR_BIT)
		{
			auto& job = g_unresolve_helpers[src->format()];

			if (!job)
			{
				const char* format_prefix = get_format_prefix(src->format());
				bool require_bgra_swap = false;

				if (vk::get_chip_family() == vk::chip_class::NV_kepler &&
					src->format() == VK_FORMAT_B8G8R8A8_UNORM)
				{
					// Workaround for NVIDIA kepler's broken image_load_store
					require_bgra_swap = true;
				}

				job.reset(new vk::cs_unresolve_task(format_prefix, require_bgra_swap));
			}

			job->run(cmd, dst, src);
		}
		else
		{
			std::vector<vk::image*> surface = {dst};
			auto& dev = cmd.get_command_pool().get_owner();

			const auto key = vk::get_renderpass_key(surface);
			auto renderpass = vk::get_renderpass(dev, key);

			if (src->aspect() & VK_IMAGE_ASPECT_STENCIL_BIT)
			{
				if (dev.get_shader_stencil_export_support())
				{
					initialize_pass(g_depthstencil_unresolver, dev);
					g_depthstencil_unresolver->run(cmd, dst, src, renderpass);
				}
				else
				{
					initialize_pass(g_depth_unresolver, dev);
					g_depth_unresolver->run(cmd, dst, src, renderpass);

					// Chance for optimization here: If the stencil buffer was not used, simply perform a clear operation
					const auto stencil_init_flags = vk::as_rtt(dst)->stencil_init_flags;
					if (stencil_init_flags & 0xFF00)
					{
						initialize_pass(g_stencil_unresolver, dev);
						g_stencil_unresolver->run(cmd, dst, src, renderpass);
					}
					else
					{
						VkClearDepthStencilValue clear{1.f, stencil_init_flags & 0xFF};
						VkImageSubresourceRange range{VK_IMAGE_ASPECT_STENCIL_BIT, 0, 1, 0, 1};

						dst->push_layout(cmd, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
						VK_GET_SYMBOL(vkCmdClearDepthStencilImage)(cmd, dst->value, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &clear, 1, &range);
						dst->pop_layout(cmd);
					}
				}
			}
			else
			{
				initialize_pass(g_depth_unresolver, dev);
				g_depth_unresolver->run(cmd, dst, src, renderpass);
			}
		}
	}

	void clear_resolve_helpers()
	{
		for (auto& task : g_resolve_helpers)
		{
			task.second->destroy();
		}

		for (auto& task : g_unresolve_helpers)
		{
			task.second->destroy();
		}

#if !defined(ANDROID) || defined(RPCSX_THOR_RSX_EXPERIMENTS)
		for (auto& task : g_resolve_blit_helpers)
		{
			task.second->destroy();
		}
#endif

		g_resolve_helpers.clear();
		g_unresolve_helpers.clear();
#if !defined(ANDROID) || defined(RPCSX_THOR_RSX_EXPERIMENTS)
		g_resolve_blit_helpers.clear();
		g_resolve_blit_scratch_images.clear();
#endif

		if (g_depth_resolver)
		{
			g_depth_resolver->destroy();
			g_depth_resolver.reset();
		}

		if (g_stencil_resolver)
		{
			g_stencil_resolver->destroy();
			g_stencil_resolver.reset();
		}

		if (g_depthstencil_resolver)
		{
			g_depthstencil_resolver->destroy();
			g_depthstencil_resolver.reset();
		}

		if (g_depth_unresolver)
		{
			g_depth_unresolver->destroy();
			g_depth_unresolver.reset();
		}

		if (g_stencil_unresolver)
		{
			g_stencil_unresolver->destroy();
			g_stencil_unresolver.reset();
		}

		if (g_depthstencil_unresolver)
		{
			g_depthstencil_unresolver->destroy();
			g_depthstencil_unresolver.reset();
		}
	}

	void reset_resolve_resources()
	{
		if (g_depth_resolver)
			g_depth_resolver->free_resources();
		if (g_depth_unresolver)
			g_depth_unresolver->free_resources();
		if (g_stencil_resolver)
			g_stencil_resolver->free_resources();
		if (g_stencil_unresolver)
			g_stencil_unresolver->free_resources();
		if (g_depthstencil_resolver)
			g_depthstencil_resolver->free_resources();
		if (g_depthstencil_unresolver)
			g_depthstencil_unresolver->free_resources();
	}

	void cs_resolve_base::build(const std::string& format_prefix, bool unresolve, bool bgra_swap)
	{
		create();

		switch (optimal_group_size)
		{
		default:
		case 64:
			cs_wave_x = 8;
			cs_wave_y = 8;
			break;
		case 32:
			cs_wave_x = 8;
			cs_wave_y = 4;
			break;
		}

		static const char* resolve_kernel =
#include "Emu/RSX/Program/MSAA/ColorResolvePass.glsl"
			;

		static const char* unresolve_kernel =
#include "Emu/RSX/Program/MSAA/ColorUnresolvePass.glsl"
			;

		const std::pair<std::string_view, std::string> syntax_replace[] =
			{
				{"%WORKGROUP_SIZE_X", std::to_string(cs_wave_x)},
				{"%WORKGROUP_SIZE_Y", std::to_string(cs_wave_y)},
				{"%IMAGE_FORMAT", format_prefix},
				{"%BGRA_SWAP", bgra_swap ? "1" : "0"}};

		m_src = unresolve ? unresolve_kernel : resolve_kernel;
		m_src = fmt::replace_all(m_src, syntax_replace);

		rsx_log.notice("Compute shader:\n%s", m_src);
	}

	void depth_resolve_base::build(bool resolve_depth, bool resolve_stencil, bool is_unresolve)
	{
		vs_src =
#include "Emu/RSX/Program/GLSLSnippets/GenericVSPassthrough.glsl"
			;

		static const char* depth_resolver =
#include "Emu/RSX/Program/MSAA/DepthResolvePass.glsl"
			;

		static const char* depth_unresolver =
#include "Emu/RSX/Program/MSAA/DepthUnresolvePass.glsl"
			;

		static const char* stencil_resolver =
#include "Emu/RSX/Program/MSAA/StencilResolvePass.glsl"
			;

		static const char* stencil_unresolver =
#include "Emu/RSX/Program/MSAA/StencilUnresolvePass.glsl"
			;

		static const char* depth_stencil_resolver =
#include "Emu/RSX/Program/MSAA/DepthStencilResolvePass.glsl"
			;

		static const char* depth_stencil_unresolver =
#include "Emu/RSX/Program/MSAA/DepthStencilUnresolvePass.glsl"
			;

		if (resolve_depth && resolve_stencil)
		{
			fs_src = is_unresolve ? depth_stencil_unresolver : depth_stencil_resolver;
		}
		else if (resolve_depth)
		{
			fs_src = is_unresolve ? depth_unresolver : depth_resolver;
		}
		else if (resolve_stencil)
		{
			fs_src = is_unresolve ? stencil_unresolver : stencil_resolver;
		}

		rsx_log.notice("Resolve shader:\n%s", fs_src);
	}
} // namespace vk
