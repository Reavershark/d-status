module d_status.main;

import d_status.config : ConfigManager;
import d_status.http_server : HttpServer;
import d_status.status_checker : StatusChecker;

import vibe.core.core : runApplication;

int main(string[] args)
{
    ConfigManager.createInstance;
    HttpServer.createInstance;
    StatusChecker.createInstance;

	return runApplication(&args);
}
