module d_status.config;

import d_status.singleton : threadLocalSingleton;

import vibe.data.json : deserializeJson;
import vibe.data.serialization : optional;

import std.exception : basicExceptionCtors, enforce;
import std.file : readText;

@safe:

class ConfigManager
{
    mixin threadLocalSingleton;

    enum ct_configFileName = "config.json";

    private Config m_config;

scope:
    private
    this()
    {
        loadConfig;
    }

    void loadConfig()
    {
        Config config = ct_configFileName.readText.deserializeJson!Config;
        config.validate;
        m_config = config;
    }

    nothrow @nogc
    const(Config) get() const
        => m_config;

    alias get this;
}

struct Config
{
    struct Category
    {
        string name;
        Site[] sites;
    }

    struct Site
    {
        string name;
        @optional string description;
        @optional string author;
        string url;
    }

    string address;
    ushort port;
    uint autoCheckIntervalSeconds; // Todo: Deserialize to duration
    uint minCheckIntervalSeconds;
    uint checkTimeoutSeconds;
    uint maxConcurrentRequests;
    Category[] categories;

    void validate() const scope
    {
        alias enf = enforce!ConfigException;

        enf(address.length);
        enf(port > 0);
        foreach (category; categories)
        {
            enf(category.name.length);
            foreach (site; category.sites)
            {
                enf(site.name.length);
                enf(site.url.length);
            }
        }
    }
}

class ConfigException : Exception
{
    mixin basicExceptionCtors;
}
