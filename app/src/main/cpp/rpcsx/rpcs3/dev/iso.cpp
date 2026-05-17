
#include "iso.hpp"
#include "util/File.h"
#include "util/types.hpp"
#include <algorithm>
#include <bit>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <memory>
#include <string>
#include <vector>

namespace
{
class iso_file_view final : public fs::file_base
{
	block_dev* m_dev;
	std::vector<iso::DirEntry> m_extents;
	u64 m_pos = 0;

public:
	iso_file_view(block_dev* dev, const iso::Entry& entry)
		: m_dev(dev), m_extents(entry.extents)
	{
	}

	fs::stat_t get_stat() override
	{
		fs::stat_t stat = m_extents.empty() ? fs::stat_t{} : m_extents.front().to_fs_stat();
		stat.size = size();
		stat.is_writable = false;
		return stat;
	}

	bool trunc(u64) override
	{
		fs::g_tls_error = fs::error::acces;
		return false;
	}

	u64 read(void* buffer, u64 count) override
	{
		const u64 result = read_at(m_pos, buffer, count);
		m_pos += result;
		return result;
	}

	u64 read_at(u64 offset, void* buffer, u64 count) override
	{
		if (!m_dev || !buffer || count == 0)
		{
			return 0;
		}

		const u64 file_size = size();
		if (offset >= file_size)
		{
			return 0;
		}

		const u64 readable = std::min<u64>(count, file_size - offset);
		const std::size_t block_size = m_dev->block_size();
		std::vector<u8> scratch;
		u8* out = static_cast<u8*>(buffer);
		u64 total = 0;

		while (total < readable)
		{
			auto [extent, extent_offset] = extent_at(offset + total);
			if (!extent)
			{
				break;
			}

			const u64 remaining = std::min<u64>(
				readable - total, extent->length.value() - extent_offset);
			const std::size_t block_index = static_cast<std::size_t>(extent_offset / block_size);
			const std::size_t block_offset = static_cast<std::size_t>(extent_offset % block_size);
			const std::size_t first_lba = extent->lba.value();

			if (block_offset == 0 && remaining >= block_size)
			{
				const std::size_t block_count =
					static_cast<std::size_t>(std::min<u64>(remaining / block_size, 64));
				const std::size_t read_blocks =
					m_dev->read(first_lba + block_index, out + total, block_count);

				if (read_blocks == 0)
				{
					break;
				}

				total += read_blocks * block_size;

				if (read_blocks < block_count)
				{
					break;
				}

				continue;
			}

			if (scratch.empty())
			{
				scratch.resize(block_size);
			}

			if (m_dev->read(first_lba + block_index, scratch.data(), 1) != 1)
			{
				break;
			}

			const u64 chunk = std::min<u64>(remaining, block_size - block_offset);
			std::memcpy(out + total, scratch.data() + block_offset, chunk);
			total += chunk;
		}

		return total;
	}

	u64 write(const void*, u64) override
	{
		fs::g_tls_error = fs::error::acces;
		return 0;
	}

	u64 write_at(u64, const void*, u64) override
	{
		fs::g_tls_error = fs::error::acces;
		return 0;
	}

	u64 seek(s64 offset, fs::seek_mode whence) override
	{
		s64 new_pos = -1;

		if (whence == fs::seek_set)
		{
			new_pos = offset;
		}
		else if (whence == fs::seek_cur)
		{
			new_pos = static_cast<s64>(m_pos) + offset;
		}
		else if (whence == fs::seek_end)
		{
			new_pos = static_cast<s64>(size()) + offset;
		}

		if (new_pos < 0)
		{
			fs::g_tls_error = fs::error::inval;
			return umax;
		}

		m_pos = static_cast<u64>(new_pos);
		return m_pos;
	}

	u64 size() override
	{
		u64 result = 0;
		for (const auto& extent : m_extents)
		{
			result += extent.length.value();
		}

		return result;
	}

private:
	std::pair<const iso::DirEntry*, u64> extent_at(u64 offset) const
	{
		for (const auto& extent : m_extents)
		{
			const u64 extent_size = extent.length.value();
			if (offset < extent_size)
			{
				return {&extent, offset};
			}

			offset -= extent_size;
		}

		return {nullptr, 0};
	}
};
} // namespace

static void append_utf8(std::string& result, char32_t codepoint)
{
	if (codepoint <= 0x7f)
	{
		result.push_back(static_cast<char>(codepoint));
	}
	else if (codepoint <= 0x7ff)
	{
		result.push_back(static_cast<char>(0xc0 | (codepoint >> 6)));
		result.push_back(static_cast<char>(0x80 | (codepoint & 0x3f)));
	}
	else if (codepoint <= 0xffff)
	{
		result.push_back(static_cast<char>(0xe0 | (codepoint >> 12)));
		result.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3f)));
		result.push_back(static_cast<char>(0x80 | (codepoint & 0x3f)));
	}
	else
	{
		result.push_back(static_cast<char>(0xf0 | (codepoint >> 18)));
		result.push_back(static_cast<char>(0x80 | ((codepoint >> 12) & 0x3f)));
		result.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3f)));
		result.push_back(static_cast<char>(0x80 | (codepoint & 0x3f)));
	}
}

static std::string u16_ne_to_string(const char16_t* bytes, std::size_t count)
{
	std::string result;
	result.reserve(count);

	for (std::size_t i = 0; i < count; ++i)
	{
		const char16_t unit = bytes[i];
		char32_t codepoint = unit;

		if (unit >= 0xd800 && unit <= 0xdbff)
		{
			if (i + 1 < count)
			{
				const char16_t trail = bytes[i + 1];
				if (trail >= 0xdc00 && trail <= 0xdfff)
				{
					codepoint = 0x10000 + (((unit - 0xd800) << 10) | (trail - 0xdc00));
					++i;
				}
				else
				{
					codepoint = 0xfffd;
				}
			}
			else
			{
				codepoint = 0xfffd;
			}
		}
		else if (unit >= 0xdc00 && unit <= 0xdfff)
		{
			codepoint = 0xfffd;
		}

		append_utf8(result, codepoint);
	}

	return result;
}

static std::string u16_se_to_string(const char16_t* bytes, std::size_t count)
{
	auto seBytes = reinterpret_cast<const se_t<char16_t, true, alignof(char16_t)>*>(bytes);

	std::vector<char16_t> neBytes(count);
	for (std::size_t i = 0; i < count; ++i)
	{
		neBytes[i] = seBytes[i];
	}

	return u16_ne_to_string(neBytes.data(), neBytes.size());
}

static std::string u16_be_to_string(const char16_t* bytes, std::size_t count)
{
	if constexpr (std::endian::native == std::endian::big)
	{
		return u16_ne_to_string(bytes, count);
	}
	else
	{
		return u16_se_to_string(bytes, count);
	}
}

static std::string decodeString(std::string_view data,
	iso::StringEncoding encoding)
{
	switch (encoding)
	{
	case iso::StringEncoding::ascii:
		break;

	case iso::StringEncoding::utf16_be:
		return u16_be_to_string(reinterpret_cast<const char16_t*>(data.data()), data.size() / 2);
	}

	return std::string(data);
}

bool iso_dev::initialize()
{
	constexpr std::size_t primaryVolumeDescOffset = 16;
	ensure(m_dev->block_size() >= sizeof(iso::VolumeHeader));
	std::vector<std::byte> block(m_dev->block_size());

	std::optional<iso::PrimaryVolumeDescriptor> primaryVolume;
	std::optional<iso::PrimaryVolumeDescriptor> supplementaryVolume;

	for (std::size_t i = 0; i < 256; ++i)
	{
		if (m_dev->read(primaryVolumeDescOffset + i, block.data(), 1) != 1)
		{
			break;
		}

		auto header = reinterpret_cast<iso::VolumeHeader*>(block.data());

		if (header->type == 255)
		{
			break;
		}

		if (std::memcmp(header->standard_id, "CD001", 5) != 0)
		{
			continue;
		}

		if (header->type == 1)
		{
			primaryVolume =
				*reinterpret_cast<iso::PrimaryVolumeDescriptor*>(block.data());
			continue;
		}

		if (header->type == 2)
		{
			std::printf("found supplementary volume\n");
			supplementaryVolume =
				*reinterpret_cast<iso::PrimaryVolumeDescriptor*>(block.data());
			continue;
		}
	}

	if (!primaryVolume)
	{
		return false;
	}

	auto& pvd = supplementaryVolume ? *supplementaryVolume : *primaryVolume;
	m_encoding = supplementaryVolume ? iso::StringEncoding::utf16_be : iso::StringEncoding::ascii;
	m_root_dir = pvd.root;

	return true;
}

bool iso_dev::stat(const std::string& path, fs::stat_t& info)
{
	auto optEntry = open_entry(path);
	if (!optEntry)
	{
		fs::g_tls_error = fs::error::noent;
		return false;
	}

	info = optEntry->to_fs_stat();
	return true;
}

bool iso_dev::statfs(const std::string& path, fs::device_stat& info)
{
	auto optEntry = open_entry(path);
	if (!optEntry)
	{
		fs::g_tls_error = fs::error::noent;
		return false;
	}

	info = {
		.block_size = m_dev->block_size(),
		.total_size = m_dev->size(),
		.total_free = 0,
		.avail_free = 0,
	};

	return true;
}

std::unique_ptr<fs::file_base> iso_dev::open(const std::string& path, rx::EnumBitSet<fs::open_mode> mode)
{
	if (mode & fs::write)
	{
		fs::g_tls_error = fs::error::acces;
		return {};
	}

	auto optEntry = open_entry(path);
	if (!optEntry)
	{
		fs::g_tls_error = fs::error::noent;
		return {};
	}

	if (optEntry->is_directory())
	{
		fs::g_tls_error = fs::error::isdir;
		return {};
	}

	return read_file(*optEntry).release();
}

std::unique_ptr<fs::dir_base> iso_dev::open_dir(const std::string& path)
{
	auto optEntry = open_entry(path);
	if (!optEntry)
	{
		fs::g_tls_error = fs::error::noent;
		return {};
	}

	if (!optEntry->is_directory())
	{
		fs::g_tls_error = fs::error::exist;
		return {};
	}

	auto items = read_dir(*optEntry);
	std::vector<fs::dir_entry> result_items(items.first.size());

	for (std::size_t i = 0; i < result_items.size(); ++i)
	{
		result_items[i] = items.first[i].to_fs_entry(items.second[i]);
	}

	return std::make_unique<fs::virtual_dir>(std::move(result_items));
}

std::optional<iso::Entry>
iso_dev::open_entry(std::string_view path)
{
	if (path == "/" || path == "\\" || path.empty())
	{
		iso::Entry root;
		root.extents.push_back(m_root_dir);
		return root;
	}

	iso::Entry item;
	item.extents.push_back(m_root_dir);

	auto isStringEqNoCase = [](std::string_view lhs, std::string_view rhs)
	{
		if (lhs.size() != rhs.size())
		{
			return false;
		}

		for (std::size_t i = 0; i < lhs.size(); ++i)
		{
			if (std::tolower(lhs[i]) != std::tolower(rhs[i]))
			{
				return false;
			}
		}

		return true;
	};

	while (!path.empty())
	{
		auto sepPos = path.find_first_of("/\\");
		if (sepPos == 0)
		{
			path.remove_prefix(1);
			continue;
		}

		if (!item.is_directory())
		{
			return {};
		}

		auto dirName = path.substr(0, sepPos);
		if (sepPos == std::string_view::npos)
		{
			path = {};
		}
		else
		{
			path.remove_prefix(sepPos);
		}

		auto items = read_dir(item);

		bool found = false;
		for (std::size_t i = 0; i < items.first.size(); ++i)
		{
			if (!isStringEqNoCase(items.second[i], dirName))
			{
				continue;
			}

			item = items.first[i];
			found = true;
			break;
		}

		if (!found)
		{
			return {};
		}
	}

	return item;
}

std::pair<std::vector<iso::Entry>, std::vector<std::string>>
iso_dev::read_dir(const iso::Entry& entry)
{
	if (!entry.is_directory())
	{
		return {};
	}

	auto block_size = m_dev->block_size();
	std::vector<iso::Entry> isoEntries;
	std::vector<std::string> names;

	for (const auto& dir_extent : entry.extents)
	{
		auto total_block_count = (dir_extent.length.value() + block_size - 1) / block_size;
		auto total_buffer_block_count = std::min<std::size_t>(total_block_count, 10);
		if (total_buffer_block_count == 0)
		{
			continue;
		}

		std::vector<std::byte> buffer(total_buffer_block_count * block_size);
		auto first_block = dir_extent.lba.value();

		for (std::size_t block = first_block, end = first_block + total_block_count;
			block < end;)
		{
			auto block_count =
				m_dev->read(block, buffer.data(), total_buffer_block_count);
			if (block_count == 0)
			{
				break;
			}

			block += block_count;

			std::size_t buffer_offset = 0;
			std::size_t buffer_size = block_count * block_size;

			while (buffer_offset < buffer_size)
			{
				auto item = reinterpret_cast<const iso::DirEntry*>(buffer.data() +
																   buffer_offset);
				if (item->entry_length == 0)
				{
					buffer_offset += block_size;
					buffer_offset &= ~(block_size - 1);
					continue;
				}

				auto filename_end =
					sizeof(iso::DirEntry) +
					((item->filename_length + 1) & ~static_cast<std::size_t>(1));

				if (item->entry_length < filename_end)
				{
					buffer_offset += item->entry_length;
					continue;
				}

				buffer_offset += item->entry_length;

				if (item->filename_length == 0 ||
					item->filename_length + sizeof(iso::DirEntry) > item->entry_length)
				{
					continue;
				}

				auto filename =
					item->filename_length > 1 ? decodeString({reinterpret_cast<const char*>(item + 1),
																 item->filename_length},
													m_encoding) :
												std::string{};

				if (item->filename_length == 1)
				{
					char c = *reinterpret_cast<const char*>(item + 1);
					// can be special name
					if (c == 0)
					{
						filename = ".";
					}
					else if (c == 1)
					{
						filename = "..";
					}
				}

				filename = filename.substr(0, filename.find(';'));
				if (filename.empty())
				{
					continue;
				}

				bool extent_merged = false;
				for (std::size_t i = 0; i < names.size(); ++i)
				{
					const auto& previous_extents = isoEntries[i].extents;
					if (names[i] == filename && !previous_extents.empty() &&
						(previous_extents.back().flags & iso::DirEntryFlags::MultiExtent) != iso::DirEntryFlags::None)
					{
						isoEntries[i].extents.push_back(*item);
						extent_merged = true;
						break;
					}
				}

				if (!extent_merged)
				{
					iso::Entry dir_entry;
					dir_entry.extents.push_back(*item);
					isoEntries.push_back(std::move(dir_entry));
					names.emplace_back(filename);
				}
			}
		}
	}

	return {std::move(isoEntries), std::move(names)};
}

fs::file iso_dev::read_file(const iso::Entry& entry)
{
	if (entry.is_directory())
	{
		return {};
	}

	if (entry.size() == 0)
	{
		return fs::make_stream<std::vector<std::uint8_t>>();
	}

	fs::file result;
	result.reset(std::make_unique<iso_file_view>(m_dev.get(), entry));
	return result;
}
