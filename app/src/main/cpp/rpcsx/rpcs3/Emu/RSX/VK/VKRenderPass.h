#pragma once

#include "VulkanAPI.h"
#include "util/geometry.h"

namespace vk
{
	class image;
	class command_buffer;

	u64 get_renderpass_key(const std::vector<vk::image*>& images, const std::vector<u8>& input_attachment_ids = {});
	u64 get_renderpass_key(const std::vector<vk::image*>& images, u64 previous_key);
	u64 get_renderpass_key(VkFormat surface_format);
	VkRenderPass get_renderpass(VkDevice dev, u64 renderpass_key);

	void clear_renderpass_cache(VkDevice dev);

	// Renderpass scope management helpers.
	// NOTE: These are not thread safe by design.
	// Fold a full-surface colour clear into the pass load op. The bit is part of
	// the key because the load op is baked into the VkRenderPass object.
	u64 renderpass_key_set_color_clear(u64 key, bool enable);
	bool renderpass_key_has_color_clear(u64 key);
	u64 renderpass_key_set_depth_clear(u64 key, bool enable);
	bool renderpass_key_has_depth_clear(u64 key);

	void begin_renderpass(VkDevice dev, const vk::command_buffer& cmd, u64 renderpass_key, VkFramebuffer target, const coordu& framebuffer_region);
	// clear_values is non-null only when the caller folded a full-surface clear
	// into the pass's load op; see the clear_color bit in VKRenderPass.cpp.
	void begin_renderpass(const vk::command_buffer& cmd, VkRenderPass pass, VkFramebuffer target, const coordu& framebuffer_region, const VkClearValue* clear_values = nullptr, u32 clear_value_count = 0);
	void end_renderpass(const vk::command_buffer& cmd);
	bool is_renderpass_open(const vk::command_buffer& cmd);

	using renderpass_op_callback_t = std::function<void(const vk::command_buffer&, VkRenderPass, VkFramebuffer)>;
	void renderpass_op(const vk::command_buffer& cmd, const renderpass_op_callback_t& op);
} // namespace vk
