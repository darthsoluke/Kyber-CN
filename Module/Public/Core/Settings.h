// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#pragma once

#include <SDK/TypeInfo.h>

#include <Windows.h>
#include <string>

namespace Kyber
{
struct MapRotationEntry
{
    MapRotationEntry(const std::string& level, const std::string& mode)
        : level(level)
        , mode(mode)
    {}

    std::string level;
    std::string mode;
};

class MapRotation
{
public:
    const MapRotationEntry* GetNextEntry()
    {
        if (m_entries.empty())
        {
            return nullptr;
        }

        if (m_current + 1 > m_entries.size())
        {
            m_current = 0;
        }

        return &m_entries[m_current++];
    }

    void Reset()
    {
        m_entries.clear();
        m_current = 0;
    }

    void AddEntry(const std::string& level, const std::string& mode)
    {
        m_entries.emplace_back(level, mode);
    }

private:
    std::vector<MapRotationEntry> m_entries;
    uint16_t m_current = 0;
};

class KyberSettingsManager
{
public:
    KyberSettingsManager();

    void RegisterSettings(const char* groupName, TypeInfo* typeInfo);
    void ApplySettings();

private:
    struct RegisteredSettings
    {
        std::string groupName;
        TypeInfo* typeInfo;
    };

    std::vector<RegisteredSettings> m_registeredSettings;
};
}
