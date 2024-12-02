/** 
 * Terminology:
 *   - Status check: Sending a request to all sites to see if they are alive
 *   - Main status check task: ...
 *   - ... task: ...
 *   - Automatic check: Check started automatically by the main task every [autoCheckInterval] minutes/hours/...
 *   - Manual check: Check started by the main task thread upon receiving a manual trigger message.
 *   - minInterval: A check can only be ran once every [minInterval] minutes/hours/...
 *   - checkTimeout: Checks will stop and fail with "timeout" if they have been running for too long.
 */
module d_status.status_checker;

@safe:

import d_status.config : Config, ConfigManager;
import d_status.singleton : threadLocalSingleton;

import core.atomic;
import core.sync.mutex : Mutex;
import core.time;

import std.algorithm;
import std.conv : to;
import std.datetime.systime : Clock, SysTime;
import std.exception : collectException;
import std.range;
import vibe.core.parallelism;
import vibe.web.common;

import requests;

import vibe.core.concurrency;
import vibe.core.core;
import vibe.core.log;

@safe:

private @trusted
auto asyncTrusted(Args...)(Args args)
    => async(args);

class StatusChecker
{
    struct CheckResult
    {
        uint code;
        bool wasRedirected;
    }

    mixin threadLocalSingleton;

    private Task m_task;
    private SysTime m_lastCheckTime;
    private bool m_doManualCheck;
    private bool m_nowChecking;
    private CheckResult[string] m_siteCheckResultMap;

scope:
    private
    this()
    {
        m_task = runTask(&taskEntrypoint);
    }

    private nothrow
    void taskEntrypoint()
    {
        try
        {
            while (true)
            {
                sleep(100.msecs);

                SysTime now = Clock.currTime;

                Duration autoCheckInterval = ConfigManager.constInstance
                    .autoCheckIntervalSeconds.seconds;
                Duration minCheckInterval = ConfigManager.constInstance
                    .minCheckIntervalSeconds.seconds;

                bool notTooFrequent = now - m_lastCheckTime > minCheckInterval;
                bool passedAutoCheckInterval = now - lastCheckTime > autoCheckInterval;

                if ((m_doManualCheck && notTooFrequent) || passedAutoCheckInterval)
                {
                    m_siteCheckResultMap = checkAll;
                    m_lastCheckTime = now;
                    m_doManualCheck = false;
                }
            }
        }
        catch (InterruptException e)
            assert(false, "StatusChecker task interrupted");
        catch (Exception e)
            assert(false);
    }

    private nothrow
    CheckResult[string] checkAll()
    {
        try
        {
            logInfo("Checking all sites");

            void wait() => sleep(5.msecs);

            uint maxConcurrentRequests = ConfigManager.constInstance.maxConcurrentRequests;
            const(Config.Site)[] sites = ConfigManager.constInstance.categories
                .map!(category => category.sites)
                .join;

            Future!CheckResult[] futures;
            futures.reserve(sites.length);

            foreach (Config.Site site; sites)
            {
                while (futures.count!(f => !f.ready) >= maxConcurrentRequests)
                    wait;
                futures ~= asyncTrusted(&checkSite, site);
            }

            while (futures.any!(f => !f.ready))
                wait;

            CheckResult[string] newSiteStatusMap;
            foreach (site, future; zip(sites, futures))
                newSiteStatusMap[site.name] = future.getResult;
            
            logInfo("Finished checking all sites");

            return newSiteStatusMap;
        }
        catch (Exception e)
            assert(false, e.msg);
    }

    private @trusted nothrow
    CheckResult checkSite(Config.Site site)
    {
        logInfo(`Checking site: "%s" ("%s")`, site.name, site.url);

        Duration checkTimeout = ConfigManager.constInstance.checkTimeoutSeconds.seconds;

        CheckResult result;
        try
        {
            Request req;
            req.sslSetCaCert("/etc/ssl/cert.pem");
            req.timeout = checkTimeout;
            Response res = req.get(site.url);

            result.code = res.code;
            if (res.uri != URI(site.url))
                result.wasRedirected = true;
        }
        catch (Exception e)
        {
            result.code = uint.max;
        }

        logInfo(`Finished checking site: "%s" ("%s")`, site.name, site.url);

        return result;
    }

    pure nothrow @nogc
    SysTime lastCheckTime() const
        => m_lastCheckTime;

    pure nothrow @nogc
    const(CheckResult[string]) siteCheckResultMap() const
        => m_siteCheckResultMap;

    pure nothrow @nogc
    void triggerManualCheck()
    {
        if (m_doManualCheck)
            return;
        if (m_nowChecking)
            return;
        m_doManualCheck = true;
    }
}
