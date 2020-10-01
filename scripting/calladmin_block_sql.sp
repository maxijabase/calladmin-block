/* Dependencies */

#include <sourcemod>
#include <regex>
#include "include/multicolors"
#include "include/calladmin"

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "2.1"

#define PREFIX "{green}[CallAdmin Block]{default}"
#define PREFIXN "[CallAdmin Block]"

/* Plugin Info */

public Plugin myinfo =  {
	
	name = "CallAdmin - Block", 
	author = "ampere", 
	description = "CallAdmin module to block people from reporting.", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/ratawar"
	
}

/* Globals */

Database g_Database;
//bool g_bIsLite;
Regex g_rSteamIdRegex;
int g_iCurrentUserInPanel;
int g_iUserUnbanTime[MAXPLAYERS + 1];
char g_cCurrentPanelSteamID[32];

/* Plugin Start */

public void OnPluginStart() {
	
	CreateConVar("sm_calladmin_block_version", PLUGIN_VERSION, "Plugin Version.", FCVAR_DONTRECORD | FCVAR_NOTIFY);
	
	RegAdminCmd("sm_calladmin_block_add", CMD_Add, ADMFLAG_GENERIC, "Add people to the block list of CallAdmin.");
	RegAdminCmd("sm_calladmin_block_remove", CMD_Remove, ADMFLAG_GENERIC, "Remove people from the block list of CallAdmin.");
	RegAdminCmd("sm_calladmin_block_list", CMD_List, ADMFLAG_GENERIC, "List all people in CallAdmin's block list.");
	
	g_rSteamIdRegex = CompileRegex("^STEAM_[\\d{1}]:[\\d{1}]:[\\d]+$");
	
	LoadTranslations("calladmin_block.phrases");
	LoadTranslations("common.phrases");
	
	Database.Connect(SQL_ConnectCallback, "calladmin_block");
	
}

/* Database */

public void SQL_ConnectCallback(Database db, const char[] error, any data) {
	
	if (db == null) {
		
		ThrowError("%s %s", PREFIXN, error);
		return;
		
	}
	
	g_Database = db;
	
	/*
	
	char driver[16];
	db.Driver.GetIdentifier(driver, sizeof(driver));
	
	g_bIsLite = !strcmp(driver, "sqlite") ? true : false;
	
	*/
	
	CreateTables();
	
}

void CreateTables() {
	
	char query[512];
	Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS calladmin_block "...
		"(id INT NOT NULL AUTO_INCREMENT, "...
		"steam_id VARCHAR(64) UNIQUE, "...
		"time_start BIGINT, time_end BIGINT, alias VARCHAR(128), "...
		"PRIMARY KEY(id));");
	
	g_Database.Query(SQL_TablesCallback, query);
	
}

public void SQL_TablesCallback(Database db, DBResultSet results, const char[] error, any data) {
	
	if (db == null || results == null) {
		
		ThrowError("%s %s", PREFIXN, error);
		delete results;
		return;
		
	}
	
	delete results;
	
}

/* Cache User Ban Times */

public void OnClientPostAdminCheck(int client) {
	
	char steamID[32];
	
	if (GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID))) {
		
		char query[512];
		Format(query, sizeof(query), "SELECT time_end FROM calladmin_block WHERE steam_id = '%s'", steamID);
		
		g_Database.Query(SQL_OnClientConnectedCacheCallback, query, GetClientUserId(client));
		
	}
	
}

public void SQL_OnClientConnectedCacheCallback(Database db, DBResultSet results, const char[] error, int userid) {
	
	if (db == null || results == null) {
		
		ThrowError("%s %s", PREFIXN, error);
		delete results;
		return;
		
	}
	
	int client = GetClientOfUserId(userid);
	int time_end;
	
	if (!results.FetchRow()) {
		
		g_iUserUnbanTime[client] = -1;
		delete results;
		return;
		
	} else {
		
		results.FieldNameToNum("time_end", time_end);
		g_iUserUnbanTime[client] = results.FetchInt(time_end);
		
	}
	
	delete results;
	
}

/* Add Command */

public Action CMD_Add(int client, int args) {
	
	char arg[128], arg1[64], arg2[64], arg3[64];
	GetCmdArgString(arg, sizeof(arg));
	
	char buf[3][32];
	
	ExplodeString(arg, " ", buf, sizeof(buf), sizeof(buf[]));
	
	strcopy(arg1, sizeof(arg1), buf[0]);
	strcopy(arg2, sizeof(arg1), buf[1]);
	strcopy(arg3, sizeof(arg1), buf[2]);
	
	char targetSteamID[64];
	bool isTarget;
	int target;
	
	if (args < 2 || arg2[0] == '\0') {
		
		CReplyToCommand(client, "%s Usage: sm_calladmin_block_add <user | STEAM_0:X:XXXXX> <time> [alias]", PREFIX);
		return Plugin_Handled;
		
	}
	
	if (!SimpleRegexMatch(arg2, "^[0-9]*$")) {
		
		CReplyToCommand(client, "%s %t", PREFIX, "Incorrect Time");
		return Plugin_Handled;
		
	}
	
	int banTime = ProcessBanTime(StringToInt(arg2));
	
	if (banTime < 0) {
		
		CReplyToCommand(client, "%s %t", PREFIX, "Time Too Long");
		return Plugin_Handled;
		
	}
	
	if (MatchRegex(g_rSteamIdRegex, arg1)) {
		
		strcopy(targetSteamID, sizeof(targetSteamID), arg1);
		isTarget = false;
		
	} else {
		
		target = FindTarget(client, arg1, true, false);
		
		if (target == -1) {
			
			return Plugin_Handled;
			
		} else {
			
			if (!GetClientAuthId(target, AuthId_Steam2, targetSteamID, sizeof(targetSteamID))) {
				
				CReplyToCommand(client, "%s %t", PREFIX, "Error Get Auth ID");
				return Plugin_Handled;
				
			}
			
			isTarget = true;
			
		}
		
	}
	
	char query[512], dbAlias[65];
	
	if (isTarget) {
		
		if (arg3[0] != '\0') {
			
			g_Database.Escape(arg3, dbAlias, sizeof(dbAlias));
			
		} else {
			
			char name[MAX_NAME_LENGTH];
			GetClientName(target, name, sizeof(name));
			g_Database.Escape(name, dbAlias, sizeof(dbAlias));
			
		}
		
		Format(query, sizeof(query), "INSERT INTO calladmin_block (steam_id, time_start, time_end, alias) "...
			"VALUES ('%s', %d, %d, '%s') "...
			"ON DUPLICATE KEY UPDATE "...
			"steam_id = '%s', "...
			"time_start = %d, "...
			"time_end = %d, "...
			"alias = '%s';", targetSteamID, GetTime(), banTime, dbAlias, targetSteamID, GetTime(), banTime, dbAlias);
		
	} else {
		
		if (arg3[0] != '\0') {
			
			g_Database.Escape(arg3, dbAlias, sizeof(dbAlias));
			Format(query, sizeof(query), "INSERT INTO calladmin_block (steam_id, time_start, time_end, alias) "...
				"VALUES ('%s', %d, %d, '%s') "...
				"ON DUPLICATE KEY UPDATE "...
				"steam_id = '%s', "...
				"time_start = %d, "...
				"time_end = %d, "...
				"alias = '%s';", targetSteamID, GetTime(), banTime, dbAlias, targetSteamID, GetTime(), banTime, dbAlias);
			
		} else {
			
			Format(query, sizeof(query), "INSERT INTO calladmin_block (steam_id, time_start, time_end) "...
				"VALUES ('%s', %d, %d) "...
				"ON DUPLICATE KEY UPDATE "...
				"steam_id = '%s', "...
				"time_start = %d, "...
				"time_end = %d;", targetSteamID, GetTime(), banTime, targetSteamID, GetTime(), banTime);
			
		}
		
	}
	
	DataPack pack = new DataPack();
	
	pack.WriteCell(!client ? client : GetClientUserId(client));
	pack.WriteCell(isTarget);
	if (isTarget)
		pack.WriteCell(GetClientUserId(target));
	
	g_Database.Query(SQL_AddCallback, query, pack);
	
	InGameAdd(target, banTime, targetSteamID, isTarget);
	
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
		
		ThrowError("%s %s", PREFIXN, error);
		delete results;
		return;
		
	}
	
	if (isTarget) {
		
		!client ? CPrintToServer("%s %t", PREFIX, "Steam ID Added Target", target) : CPrintToChat(client, "%s %t", PREFIX, "Steam ID Added Target", target);
		
	} else {
		
		!client ? CPrintToServer("%s %t", PREFIX, "Steam ID Added") : CPrintToChat(client, "%s %t", PREFIX, "Steam ID Added");
		
	}
	
	delete results;
	
}

/* Remove Command */

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
			
		} else {
			
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
	
	InGameRemove(target, targetSteamID, isTarget);
	
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
		
		ThrowError("%s %s", PREFIXN, error);
		delete results;
		return;
		
	}
	
	if (results.AffectedRows) {
		
		if (isTarget) {
			
			!client ? CPrintToServer("%s %t", PREFIX, "Steam ID Removed Target", target) : CPrintToChat(client, "%s %t", PREFIX, "Steam ID Removed Target", target);
			
		} else {
			
			!client ? CPrintToServer("%s %t", PREFIX, "Steam ID Removed") : CPrintToChat(client, "%s %t", PREFIX, "Steam ID Removed");
			
		}
		
	} else {
		
		if (isTarget) {
			
			!client ? CPrintToServer("%s %t", PREFIX, "Steam ID Not In Blocklist Target", target) : CPrintToChat(client, "%s %t", PREFIX, "Steam ID Not In Blocklist Target", target);
			
		} else {
			
			!client ? CPrintToServer("%s %t", PREFIX, "Steam ID Not In Blocklist") : CPrintToChat(client, "%s %t", PREFIX, "Steam ID Not In Blocklist");
			
		}
		
	}
	
	delete results;
	
}

/* List Command */

public Action CMD_List(int client, int args) {
	
	if (!client) {
		
		CReplyToCommand(client, "%s This command cannot be executed from the console.", PREFIX);
		return Plugin_Handled;
		
	}
	
	ShowBanList(client);
	
	return Plugin_Handled;
	
}

void ShowBanList(int client) {
	
	char query[512];
	Format(query, sizeof(query), "SELECT steam_id, alias FROM calladmin_block");
	
	g_Database.Query(SQL_ListCallback, query, GetClientUserId(client));
	
}

public void SQL_ListCallback(Database db, DBResultSet results, const char[] error, int userid) {
	
	if (db == null || results == null) {
		
		ThrowError("%s %s", PREFIXN, error);
		delete results;
		return;
		
	}
	
	int client = GetClientOfUserId(userid);
	
	if (!results.FetchRow()) {
		
		CPrintToChat(client, "%s %t", PREFIX, "No Information");
		delete results;
		return;
		
	}
	
	int steamidCol, aliasCol, count;
	char steamID[32], alias[64], menuLine[128], idx[2];
	
	results.FieldNameToNum("steam_id", steamidCol);
	results.FieldNameToNum("alias", aliasCol);
	
	Menu menu = new Menu(menuHandler, MENU_ACTIONS_ALL);
	
	menu.SetTitle("%t", "List of Steam IDs");
	
	do {
		
		count++;
		IntToString(count, idx, sizeof(idx));
		
		results.FetchString(steamidCol, steamID, sizeof(steamID));
		results.FetchString(aliasCol, alias, sizeof(alias));
		
		alias[0] ? Format(menuLine, sizeof(menuLine), "%s (%s)", steamID, alias) : Format(menuLine, sizeof(menuLine), "%s", steamID);
		
		menu.AddItem(idx, menuLine);
		
	} while (results.FetchRow());
	
	menu.ExitButton = true;
	menu.Display(client, 20);
	delete results;
	
}

public int menuHandler(Menu menu, MenuAction action, int param1, int param2) {
	
	switch (action) {
		
		case MenuAction_Select: {
			
			g_iCurrentUserInPanel = param2;
			ShowBannedClientPanel(GetClientUserId(param1), param2);
			
		}
		
		case MenuAction_End: {
			
			delete menu;
			
		}
		
	}
	
}

void ShowBannedClientPanel(int userid, int offset) {
	
	char query[512];
	Format(query, sizeof(query), "SELECT * FROM calladmin_block LIMIT %i,1", offset);
	
	g_Database.Query(SQL_BannedClientPanelCallback, query, userid);
	
}

public void SQL_BannedClientPanelCallback(Database db, DBResultSet results, const char[] error, int userid) {
	
	if (db == null || results == null) {
		
		ThrowError("%s %s", PREFIXN, error);
		delete results;
		return;
		
	}
	
	if (!results.FetchRow()) {
		
		delete results;
		return;
		
	}
	
	int client = GetClientOfUserId(userid);
	int steamIdCol, timeStartCol, timeEndCol, aliasCol;
	
	char panelTitle[64];
	char steamID[32], timeStart[32], timeEnd[32], alias[32];
	char timeStartFormatted[64], timeEndFormatted[64];
	char line1[32], line2[32], line3[32], line4[32];
	char exitString[16], backString[16], removeUser[32];
	
	Panel banPanel = new Panel();
	
	results.FieldNameToNum("steam_id", steamIdCol);
	results.FieldNameToNum("time_start", timeStartCol);
	results.FieldNameToNum("time_end", timeEndCol);
	results.FieldNameToNum("alias", aliasCol);
	
	results.FetchString(steamIdCol, steamID, sizeof(steamID));
	results.FetchString(timeStartCol, timeStart, sizeof(timeStart));
	results.FetchString(timeEndCol, timeEnd, sizeof(timeEnd));
	results.FetchString(aliasCol, alias, sizeof(alias));
	
	strcopy(g_cCurrentPanelSteamID, sizeof(g_cCurrentPanelSteamID), steamID);
	
	FormatTime(timeStartFormatted, sizeof(timeStartFormatted), "%F %R", StringToInt(timeStart));
	
	if (StringToInt(timeEnd) == 0) {
		
		Format(timeEndFormatted, sizeof(timeEndFormatted), "%t", "Permaban");
		
	} else {
		
		FormatTime(timeEndFormatted, sizeof(timeEndFormatted), "%F %R", StringToInt(timeEnd));
		
	}
	
	Format(line1, sizeof(line1), "Steam ID: %s", steamID);
	
	if (alias[0]) {
		
		Format(line2, sizeof(line2), "%t: %s", "Alias", alias);
		
	} else {
		
		Format(line2, sizeof(line2), "%t: %t", "Alias", "No Alias");
		
	}
	
	Format(line3, sizeof(line3), "%t: %s", "Date Of Issue", timeStartFormatted);
	Format(line4, sizeof(line4), "%t: %s", "Date Of End", timeEndFormatted);
	
	Format(panelTitle, sizeof(panelTitle), "%t", "Showing Ban Status", steamID);
	banPanel.SetTitle(panelTitle);
	
	Format(exitString, sizeof(exitString), "%t", "Exit");
	Format(backString, sizeof(backString), "%t", "Back");
	Format(removeUser, sizeof(removeUser), "%t", "Remove User");
	
	banPanel.DrawText(" ");
	banPanel.DrawText(line1);
	banPanel.DrawText(line2);
	banPanel.DrawText(line3);
	banPanel.DrawText(line4);
	banPanel.DrawText(" ");
	banPanel.DrawItem(removeUser);
	banPanel.DrawItem(backString);
	banPanel.CurrentKey = 10;
	banPanel.DrawItem(exitString);
	
	banPanel.Send(client, banPanelHandler, 20);
	
	delete results;
	delete banPanel;
	
}

public int banPanelHandler(Menu menu, MenuAction action, int param1, int param2) {
	
	switch (action) {
		
		case MenuAction_Select: {
			
			switch (param2) {
				
				case 1: {
					
					DeleteMenuEntry(param1);
					InGameRemove(_, g_cCurrentPanelSteamID, false);
					ShowBanList(param1);
					
				}
				
				case 2: {
					
					ShowBanList(param1);
					
				}
				
				case 10: {
					
					delete menu;
					
				}
				
			}
			
		}
		
		case MenuAction_End: {
			
			delete menu;
			
		}
		
	}
	
}

void DeleteMenuEntry(int client) {
	
	char query[512];
	Format(query, sizeof(query), "DELETE c1 FROM calladmin_block c1 "...
		"INNER JOIN (SELECT steam_id FROM calladmin_block ORDER BY id LIMIT %i,1) "...
		"AS c2 ON c2.steam_id = c1.steam_id;", g_iCurrentUserInPanel);
	
	g_Database.Query(SQL_DeleteMenuEntryCallback, query, GetClientUserId(client));
	
}

public void SQL_DeleteMenuEntryCallback(Database db, DBResultSet results, const char[] error, int userid) {
	
	if (db == null || results == null) {
		
		ThrowError("%s %s", PREFIXN, error);
		delete results;
		return;
		
	}
	
	int client = GetClientOfUserId(userid);
	
	CPrintToChat(client, "%s %t", PREFIX, "Steam ID Removed");
	
	delete results;
	
}

/* CallAdmin Menu Draw Forward */

public Action CallAdmin_OnDrawMenu(int client) {
	
	if ((GetTime() < g_iUserUnbanTime[client] || g_iUserUnbanTime[client] == 0) && g_iUserUnbanTime[client] != -1) {
		
		CPrintToChat(client, "%s %t", PREFIX, "Not Allowed");
		return Plugin_Handled;
		
	}
	
	return Plugin_Continue;
	
}

/* In Game Stocks (to update user ban time caches on the go and return ban times) */

void InGameAdd(int target, int banEnd, const char[] targetSteamID, bool isTarget) {
	
	if (isTarget) {
		
		g_iUserUnbanTime[target] = banEnd;
		return;
		
	} else {
		
		char steamID[32];
		
		for (int i = 1; i <= MaxClients; i++) {
			
			if (IsClientInGame(i) && !IsFakeClient(i) && GetClientAuthId(i, AuthId_Steam2, steamID, sizeof(steamID))) {
				
				if (StrEqual(targetSteamID, steamID)) {
					
					g_iUserUnbanTime[i] = banEnd;
					return;
					
				}
				
			}
			
		}
		
	}
	
}


void InGameRemove(int target = 1, const char[] targetSteamID = "", bool isTarget = false) {
	
	if (isTarget) {
		
		g_iUserUnbanTime[target] = -1;
		return;
		
	} else {
		
		char steamID[32];
		
		for (int i = 1; i <= MaxClients; i++) {
			
			if (IsClientInGame(i) && !IsFakeClient(i) && GetClientAuthId(i, AuthId_Steam2, steamID, sizeof(steamID))) {
				
				if (StrEqual(targetSteamID, steamID)) {
					
					g_iUserUnbanTime[i] = -1;
					return;
					
				}
				
			}
			
		}
		
	}
	
}


stock int ProcessBanTime(int time) {
	
	return time == 0 ? 0 : (GetTime() + (time * 60));
	
} 