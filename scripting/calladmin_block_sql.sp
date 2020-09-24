/*

TODO
	fix commands from console (print vs reply)
	make sqlite queries


*/

#include <sourcemod>
#include <regex>
#include "include/multicolors"
#include "include/calladmin"

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "2.0"
#define PREFIX "{green}[CallAdmin Block]{default}"

public Plugin myinfo =  {
	
	name = "CallAdmin - Block", 
	author = "ampere", 
	description = "CallAdmin module to block people from reporting.", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/ratawar"
	
}

Database g_Database;
bool g_bIsLite;
Regex g_rSteamIdRegex;
bool g_bIsClientBlocked[MAXPLAYERS + 1];

public void OnPluginStart() {
	
	CreateConVar("sm_calladmin_block_version", PLUGIN_VERSION, "Plugin Version.", FCVAR_DONTRECORD);
	
	RegAdminCmd("sm_calladmin_block_add", CMD_Add, ADMFLAG_GENERIC, "Add people to the block list of CallAdmin.");
	RegAdminCmd("sm_calladmin_block_remove", CMD_Remove, ADMFLAG_GENERIC, "Remove people from the block list of CallAdmin.");
	RegAdminCmd("sm_calladmin_block_list", CMD_List, ADMFLAG_GENERIC, "List all people in CallAdmin's block list.");
	
	g_rSteamIdRegex = CompileRegex("^STEAM_[\\d{1}]:[\\d{1}]:[\\d]+$");
	
	LoadTranslations("calladmin_block.phrases");
	LoadTranslations("common.phrases");
	
	Database.Connect(SQL_ConnectCallback, "calladmin_block");
	
}

public void SQL_ConnectCallback(Database db, const char[] error, any data) {
	
	if (db == null) {
		
		ThrowError("%s %s", PREFIX, error);
		return;
		
	}
	
	g_Database = db;
	
	char driver[16];
	db.Driver.GetIdentifier(driver, sizeof(driver));
	
	g_bIsLite = !strcmp(driver, "sqlite") ? true : false;
	
	CreateTables();
	
}

void CreateTables() {
	
	char query[512];
	Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS calladmin_block (steam_id VARCHAR(64), "...
		"time_start BIGINT, time_end BIGINT, alias VARCHAR(128), "...
		"unique(steam_id));");
	
	g_Database.Query(SQL_TablesCallback, query);
	
}

public void SQL_TablesCallback(Database db, DBResultSet results, const char[] error, any data) {
	
	if (db == null || results == null) {
		
		ThrowError("%s %s", PREFIX, error);
		return;
		
	}
	
}

public Action CMD_Add(int client, int args) {
	
	if (args < 2) {
		
		CReplyToCommand(client, "%s Usage: sm_calladmin_block_add <user | STEAM_0:X:XXXXX> <time> [alias]", PREFIX);
		return Plugin_Handled;
		
	}
	
	char arg[128], arg1[64], arg2[64], arg3[64];
	GetCmdArgString(arg, sizeof(arg));
	
	/* <explode> */
	
	char buf[3][32];
	
	ExplodeString(arg, " ", buf, sizeof(buf), sizeof(buf[]));
	
	strcopy(arg1, sizeof(arg1), buf[0]);
	strcopy(arg2, sizeof(arg1), buf[1]);
	strcopy(arg3, sizeof(arg1), buf[2]);
	
	/* </explode> */
	
	PrintToServer(arg1);
	PrintToServer(arg2);
	PrintToServer(arg3);
	
	char targetSteamID[64];
	bool isTarget;
	int target;
	
	if (!SimpleRegexMatch(arg2, "^[0-9]*$")) {
		
		CReplyToCommand(client, "%s %t", PREFIX, "Incorrect Time");
		return Plugin_Handled;
		
	}
	
	if (MatchRegex(g_rSteamIdRegex, arg1)) {
		
		strcopy(targetSteamID, sizeof(targetSteamID), arg1);
		isTarget = false;
		
	} else {
		
		target = FindTarget(client, arg1, true, false);
		
		if (target == -1) {
			
			return Plugin_Handled;
			
		}
		
		else {
			
			if (!GetClientAuthId(target, AuthId_Steam2, targetSteamID, sizeof(targetSteamID))) {
				
				CReplyToCommand(client, "%s %t", PREFIX, "Error Get Auth ID");
				return Plugin_Handled;
				
			}
			
			isTarget = true;
			
		}
		
	}
	
	char query[512];
	char dbAlias[65];
	
	if (isTarget) {
		
		if (arg3[0] != '\0') {
			
			g_Database.Escape(arg3, dbAlias, sizeof(dbAlias));
			
		}
		
		else {
			
			char name[MAX_NAME_LENGTH];
			GetClientName(target, name, sizeof(name));
			g_Database.Escape(name, dbAlias, sizeof(dbAlias));
			
		}
		
		Format(query, sizeof(query), "INSERT INTO calladmin_block (steam_id, time_start, time_end, alias) "...
			"VALUES ('%s', %d, %d, '%s') "...
			"ON DUPLICATE KEY UPDATE steam_id = '%s';", targetSteamID, GetTime(), ProcessTime(StringToInt(arg2)), dbAlias, targetSteamID);
		
	}
	
	else {
		
		if (arg3[0] != '\0') {
			
			g_Database.Escape(arg3, dbAlias, sizeof(dbAlias));
			Format(query, sizeof(query), "INSERT INTO calladmin_block (steam_id, time_start, time_end, alias) "...
				"VALUES ('%s', %d, %d, '%s') "...
				"ON DUPLICATE KEY UPDATE steam_id = '%s';", targetSteamID, GetTime(), ProcessTime(StringToInt(arg2)), dbAlias, targetSteamID);
		}
		
		else {
			
			Format(query, sizeof(query), "INSERT INTO calladmin_block (steam_id, time_start, time_end, alias) "...
				"VALUES ('%s', %d, %d) "...
				"ON DUPLICATE KEY UPDATE steam_id = '%s';", targetSteamID, GetTime(), ProcessTime(StringToInt(arg2)), targetSteamID);
			
		}
		
	}
	
	DataPack pack = new DataPack();
	
	pack.WriteCell(!client ? client : GetClientUserId(client));
	pack.WriteCell(isTarget);
	if (isTarget)
		pack.WriteCell(GetClientUserId(target));
	
	g_Database.Query(SQL_AddCallback, query, pack);
	
	return Plugin_Handled;
	
}

public void SQL_AddCallback(Database db, DBResultSet results, const char[] error, DataPack pack) {
	
	pack.Reset();
	int client = pack.ReadCell();
	bool isTarget = pack.ReadCell();
	int target;
	
	if (isTarget) {
		
		target = GetClientOfUserId(pack.ReadCell());
		
	}
	
	if (client != 0) {
		
		client = GetClientOfUserId(client);
		
	}
	
	delete pack;
	
	if (db == null || results == null) {
		
		ThrowError("%s %s", PREFIX, error);
		return;
		
	}
	
	if (results.AffectedRows) {
		
		if (isTarget) {
			
			CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Added Target", target);
			
		}
		
		else {
			
			CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Added");
			
		}
		
	} else {
		
		if (isTarget) {
			
			CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Already Blocked Target", target);
			
		}
		
		else {
			
			CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Already Blocked");
			
		}
		
	}
	
}

public Action CMD_Remove(int client, int args) {
	
	if (!args) {
		
		CReplyToCommand(client, "%s Usage: sm_calladmin_block_remove <user | STEAM_0:X:XXXXX>", PREFIX);
		return Plugin_Handled;
		
	}
	
	char arg1[64];
	GetCmdArgString(arg1, sizeof(arg1));
	
	char targetSteamID[32];
	bool isTarget;
	int target;
	
	if (MatchRegex(g_rSteamIdRegex, arg1)) {
		
		strcopy(targetSteamID, sizeof(targetSteamID), arg1);
		isTarget = false;
		
	} else {
		
		target = FindTarget(client, arg1, true, false);
		
		if (target == -1) {
			
			return Plugin_Handled;
			
		}
		
		else {
			
			if (!GetClientAuthId(target, AuthId_Steam2, targetSteamID, sizeof(targetSteamID))) {
				
				CReplyToCommand(client, "%s %t", PREFIX, "Error Get Auth ID");
				return Plugin_Handled;
				
			}
			
			isTarget = true;
			
		}
		
	}
	
	char query[512];
	Format(query, sizeof(query), "DELETE FROM calladmin_block WHERE steam_id = '%s'", targetSteamID);
	
	DataPack pack = new DataPack();
	
	pack.WriteCell(!client ? client : GetClientUserId(client));
	pack.WriteCell(isTarget);
	
	if (isTarget) {
		
		pack.WriteCell(GetClientUserId(target));
		
	}
	
	g_Database.Query(SQL_RemoveCallback, query, pack);
	
	return Plugin_Handled;
	
}

public void SQL_RemoveCallback(Database db, DBResultSet results, const char[] error, DataPack pack) {
	
	pack.Reset();
	int client = pack.ReadCell();
	bool isTarget = pack.ReadCell();
	int target;
	
	if (isTarget) {
		
		target = GetClientOfUserId(pack.ReadCell());
		
	}
	
	if (client != 0) {
		
		client = GetClientOfUserId(client);
		
	}
	
	delete pack;
	
	if (db == null || results == null) {
		
		ThrowError("%s %s", PREFIX, error);
		return;
		
	}
	
	if (results.AffectedRows) {
		
		if (isTarget) {
			
			CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Removed Target", target);
			
		}
		
		else {
			
			CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Removed");
			
		}
		
	}
	
	else {
		
		if (isTarget) {
			
			CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Not In Blocklist Target", target);
			
		}
		
		else {
			
			CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Not In Blocklist");
			
		}
		
	}
	
}

public Action CMD_List(int client, int args) {
	
	if (!client) {
		
		ReplyToCommand(client, "%s This command cannot be executed from the console.");
		return Plugin_Handled;
		
	}
	
	char query[512];
	Format(query, sizeof(query), "SELECT steam_id, alias FROM calladmin_block");
	
	g_Database.Query(SQL_ListCallback, query, GetClientUserId(client));
	
	return Plugin_Handled;
	
}

public void SQL_ListCallback(Database db, DBResultSet results, const char[] error, int userid) {
	
	if (db == null || results == null) {
		
		ThrowError("%s %s", PREFIX, error);
		return;
		
	}
	
	int client = GetClientOfUserId(userid);
	
	if (!results.FetchRow()) {
		
		CReplyToCommand(client, "%s %t", PREFIX, "No Information");
		return;
		
	}
	
	int steamidCol, aliasCol, count;
	char steamid[32], alias[64];
	
	results.FieldNameToNum("steam_id", steamidCol);
	results.FieldNameToNum("alias", aliasCol);
	
	Panel panel = new Panel();
	char panelTitle[32];
	Format(panelTitle, sizeof(panelTitle), "%t", "List of Steam IDs");
	
	panel.SetTitle(panelTitle);
	
	do {
		
		count++;
		results.FetchString(steamidCol, steamid, sizeof(steamid));
		results.FetchString(aliasCol, alias, sizeof(alias));
		
		char panelLine[128];
		
		if (alias[0]) {
			
			Format(panelLine, sizeof(panelLine), "%i- %s (%s)", count, steamid, alias);
			
		}
		
		else {
			
			Format(panelLine, sizeof(panelLine), "%i- %s", count, steamid);
			
		}
		
		panel.DrawText(panelLine);
		
	} while (results.FetchRow());
	
	panel.DrawText("");
	panel.CurrentKey = 10;
	panel.DrawItem("Exit");
	panel.Send(client, panelHandler, MENU_TIME_FOREVER);
	
	delete panel;
	
}

public int panelHandler(Menu menu, MenuAction action, int param1, int param2) {
	
	switch (action) {
		
		case MenuAction_End, MenuAction_Cancel: {
			
			delete menu;
			
		}
		
	}
	
}

public Action CallAdmin_OnDrawMenu(int client) {
	
	char steamid[32];
	
	if (!GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid))) {
		
		LogError("%s Error while attempting to fetch client's Auth ID", PREFIX);
		return Plugin_Handled;
		
	}
	
	if (g_bIsClientBlocked[client]) {
		
		CReplyToCommand(client, "%s %t", PREFIX, "Not Allowed");
		return Plugin_Handled;
		
	}
	
	return Plugin_Continue;
	
}

stock int ProcessTime(int time) {
	
	return (GetTime() + (time * 60));
	
} 