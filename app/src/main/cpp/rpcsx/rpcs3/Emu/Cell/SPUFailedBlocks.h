#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <map>
#include <utility>

// Store disjoint local-store ranges that the SPU backend cannot compile.
class spu_failed_block_set
{
public:
	bool mark(std::uint32_t begin, std::uint32_t end)
	{
		if (end <= begin)
		{
			return false;
		}

		if (const auto covering = range_of(begin); covering.first <= begin && covering.second >= end)
		{
			return false;
		}

		auto it = m_map.upper_bound(begin);

		if (it != m_map.begin())
		{
			auto previous = std::prev(it);

			if (previous->second >= begin)
			{
				begin = previous->first;
				end = std::max(end, previous->second);
				it = m_map.erase(previous);
			}
		}

		while (it != m_map.end() && it->first <= end)
		{
			end = std::max(end, it->second);
			it = m_map.erase(it);
		}

		m_map.emplace(begin, end);
		return true;
	}

	std::pair<std::uint32_t, std::uint32_t> range_of(std::uint32_t address) const
	{
		auto it = m_map.upper_bound(address);

		if (it == m_map.begin())
		{
			return {};
		}

		--it;

		if (address >= it->first && address < it->second)
		{
			return {it->first, it->second};
		}

		return {};
	}

	bool contains(std::uint32_t address) const
	{
		const auto range = range_of(address);
		return range.second > range.first;
	}

	void clear()
	{
		m_map.clear();
	}

private:
	std::map<std::uint32_t, std::uint32_t> m_map;
};
