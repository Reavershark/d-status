module d_status.http_server;

import d_status.config : Config, ConfigManager;
import d_status.singleton : threadLocalSingleton;
import d_status.status_checker : StatusChecker;

import core.time : Duration, msecs, seconds;

import std.datetime.systime : Clock, SysTime;
import std.format : f = format;

import vibe.core.core : sleep;
import vibe.http.fileserver : serveStaticFiles;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPListener, HTTPServerRequest, HTTPServerResponse, HTTPServerSettings, listenHTTP, render;
import vibe.http.status : HTTPStatus;

@safe:

class HttpServer
{
	mixin threadLocalSingleton;

	private HTTPServerSettings m_settings;
	private URLRouter m_router;
	private HTTPListener m_listener;

scope:
	private
	this()
	{
		m_settings = new HTTPServerSettings;
		m_settings.bindAddresses = [ConfigManager.instance.address];
		m_settings.port = ConfigManager.instance.port;

		m_router = new URLRouter;
		m_router.get("/", &getIndex);
		m_router.post("/triggerManualCheck", &postTriggerManualCheck);
		m_router.get("*", serveStaticFiles("public/"));

		m_listener = listenHTTP(m_settings, m_router);
	}

	void getIndex(scope HTTPServerRequest req, scope HTTPServerResponse res)
	{
		res.headers["Content-Type"] = "text/html";
		res.render!("index.dt");
	}

	void postTriggerManualCheck(scope HTTPServerRequest req, scope HTTPServerResponse res)
	{
		Duration minCheckInterval = ConfigManager.constInstance
			.minCheckIntervalSeconds.seconds;
		SysTime previousCheckTime = StatusChecker.constInstance.lastCheckTime;
		SysTime now = Clock.currTime;
		previousCheckTime.fracSecs = Duration.zero;
		now.fracSecs = Duration.zero;
		Duration diff = now - previousCheckTime;

		if (diff < minCheckInterval)
		{
			res.statusCode = HTTPStatus.tooManyRequests;
			res.writeBody(f!"Please wait %s before checking again"(minCheckInterval - diff));
			return;
		}

		StatusChecker.instance.triggerManualCheck;
		while (previousCheckTime == StatusChecker.constInstance.lastCheckTime)
			sleep(100.msecs);
		res.statusCode = HTTPStatus.noContent;
		res.writeBody("");
	}
}
