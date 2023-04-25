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
module status_check;
@safe:

import vibe.core.core;
import vibe.core.concurrency;
import vibe.core.log;

import core.time;
import std.datetime.systime : SysTime, Clock;
import core.sync.mutex : Mutex;
import core.atomic;
import std.conv : to;

import site;

auto async_trusted(Args...)(Args args) @trusted => async(args);

enum autoCheckInterval = 1.hours;
enum minInterval = 2.minutes;
enum checkTimeout = 10.seconds;

shared class MainTask
{
private:
    Task task;

public:
    Category[] categories;
    bool unseenCategoriesChange = false;
    Mutex categoriesMutex;
    bool shouldDoManualCheck = false;
    bool tooManyChecks = false;

    this(scope shared Category[] categories_arg)
    {
        categoriesMutex = new shared Mutex;

        categoriesMutex.lock;
        categories = categories_arg.dup;
        // Deep copy
        foreach (ref shared Category category; categories)
            category.sites = category.sites.dup;
        categoriesMutex.unlock;

        TaskSettings settings;
        settings.priority = Task.basePriority * 2;
        this.task = runTask(settings, () nothrow @safe { taskEntrypoint; });
    }

    void triggerManualCheck()
    {
        if (shouldDoManualCheck)
        {
            // Check in progress
            tooManyChecks = true;
            return;
        }

        tooManyChecks = false;
        shouldDoManualCheck = true;
    }

private:
    void taskEntrypoint() nothrow
    {
        try
        {
            // Set the last check long enough ago so that a new automatic check is triggered right away
            SysTime lastCheck = Clock.currTime - autoCheckInterval;

            while (true)
            {
                SysTime now = Clock.currTime;

                if (shouldDoManualCheck)
                {
                    if (now - lastCheck > minInterval)
                    {
                        logInfo("Running manual check (%s)", now);
                        doChecks;
                        lastCheck = now;
                    }
                    else
                    {
                        tooManyChecks = true;
                    }
                    shouldDoManualCheck = false;
                }

                // if received manual trigger message, doChecks if not checked in the last minute
                // else if now - lastCheck > 15.mins, doChecks
                else if (now - lastCheck > autoCheckInterval)
                {
                    logInfo("Running automatic check (%s)", now);
                    doChecks;
                    lastCheck = now;
                }

                sleep(100.msecs);
            }
        }
        catch (Exception e)
        {
            () @trusted {
                logError("Exception in main status check task: %s", e);
            }();
        }
    }

    void doChecks()
    {
        categoriesMutex.lock;
        scope (exit)
            categoriesMutex.unlock;

        struct CheckResult
        {
            int code;
            bool wasRedirected;
        }

        Future!CheckResult[] checkers;

        foreach (shared Category category; categories)
            foreach (Site site; category.sites)
            {
                logInfo("Starting checker for site: \"%s\" (\"%s\")", site.name, site.url);

                CheckResult checkerEntrypoint(Site site) nothrow @safe
                {
                    import requests;

                    int code = 0;
                    bool wasRedirected = false;
                    try
                    {
                        Response res = () @trusted {
                            // This is @system code
                            Request req;
                            req.sslSetCaCert("/etc/ssl/cert.pem");
                            return req.get(site.url);
                        }();

                        code = res.code;
                        wasRedirected = res.uri != URI(site.url);
                    }
                    catch (Exception e)
                    {
                        code = -1;
                    }

                    logInfo("Finished checking site: \"%s\" (\"%s\")", site.name, site.url);
                    return CheckResult(code, wasRedirected);
                }

                checkers ~= async_trusted(&checkerEntrypoint, site);
            }

        sleep(checkTimeout);

        size_t i = 0;
        foreach (ref shared Category category; categories)
            foreach (ref shared Site site; category.sites)
            {
                Future!CheckResult checker = checkers[i];
                CheckResult result;
                if (!checker.ready)
                {
                    if (checker.task.running)
                    {
                        checker.task.interrupt;
                    }
                    // Failed with timeout
                    result = CheckResult(-1, false);
                }
                else
                {
                    // Succeeded or failed, indicated by http status code
                    result = checker.getResult();
                }

                logInfo("Result for %s: %s, %s, %s", site.name, result.code, result.wasRedirected,
                    Clock.currTime);

                site.lastCode = result.code;
                unseenCategoriesChange = true;

                i++;
            }
    }
}
