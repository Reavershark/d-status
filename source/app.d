import std.stdio;
import std.range;
import std.algorithm;

import vibe.core.core : runApplication, sleep;
import vibe.http.server;
import vibe.http.router;

import vibe.inet.url : InetPath;

import std.datetime.interval : Interval;

import site;
import status_check;

import core.time;
import std.datetime.systime;
import vibe.http.fileserver;

import std.process : environment;
import std.conv : to;

shared Category[] categories;
shared MainTask mainTask;
SysTime lastCheck;

void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res)
@safe
{
	res.headers["Content-Type"] = "text/html";

	if (req.requestPath == InetPath("/triggerManualCheck"))
	{
		mainTask.triggerManualCheck;
		// Wait for the check to complete by watching unseenCategoriesChange
		while (true)
		{
			{
				if (mainTask.unseenCategoriesChange)
				{
					res.redirect("/");
					return;
				}
				else if (mainTask.tooManyChecks)
				{
					res.writeBody("Error:<br>Another check was just done, please wait a while.");
					return;
				}
			}
			sleep(100.msecs);
		}
	}

	if (mainTask.categoriesMutex.tryLock)
	{
		if (mainTask.unseenCategoriesChange)
		{
			categories = mainTask.categories.dup;
			mainTask.unseenCategoriesChange = false;
			lastCheck = Clock.currTime;
		}
		mainTask.categoriesMutex.unlock;
	}

	res.render!("index.dt", categories, lastCheck);
}

int main(string[] args)
{
	import std.file : readText;
	import std.json : parseJSON, JSONValue;
	import std.algorithm : map;
	import std.array : array;

	categories = cast(shared(Category[])) readText("sites.json")
		.parseJSON
		.objectNoRef["categories"]
		.arrayNoRef
		.map!((JSONValue category) {
			return Category(
				category["name"].str,
				category["sites"]
				.arrayNoRef
				.map!((JSONValue site) => Site(
				site["name"].str,
				("description" in site) ? site["description"].str : "",
				("author" in site) ? site["author"].str : "",
				site["url"]
				.str))
				.array
			);
		})
		.array;

	mainTask = new shared MainTask(categories);

	auto settings = new HTTPServerSettings;

	settings.bindAddresses = [
		("LISTEN_ADDRESS" in environment) ? environment["LISTEN_ADDRESS"]: "127.0.0.1"
	];
	settings.port = ("LISTEN_PORT" in environment) ? environment["LISTEN_PORT"].to!ushort : 8080;

	URLRouter router = new URLRouter;
	router.get("/", &handleRequest);
	router.get("/triggerManualCheck", &handleRequest);
	router.get("*", serveStaticFiles("public/"));

	listenHTTP(settings, router);

	return runApplication(&args);
}
