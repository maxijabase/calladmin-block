#include <sourcemod>
#include <regex>
#include "include/multicolors"
#include "include/calladmin"

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"
#define PREFIX "{green}[CallAdmin Block]{default}"

public Plugin myinfo =  {
	
	name = "CallAdmin - Block", 
	author = "ampere", 
	description = "CallAdmin module to block people from reporting.", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/ratawar"
	
}

char g_cConfigFile[PLATFORM_MAX_PATH];
Regex g_rSteamIdRegex;
bool g_bIsClientBlocked[MAXPLAYERS + 1];

public void OnPluginStart() {
	
	CreateConVar("sm_calladmin_block_version", PLUGIN_VERSION, "Plugin Version.", FCVAR_DONTRECORD);
	
	RegAdminCmd("sm_calladmin_block_add", CMD_Add, ADMFLAG_GENERIC, "Add people to the block list of CallAdmin.");
	RegAdminCmd("sm_calladmin_block_remove", CMD_Remove, ADMFLAG_GENERIC, "Remove people from the block list of CallAdmin.");
	RegAdminCmd("sm_calladmin_block_list", CMD_List, ADMFLAG_GENERIC, "List all people in CallAdmin's block list.");
	
	g_rSteamIdRegex = CompileRegex("^STEAM_[\\d{1}]:[\\d{1}]:[\\d]+$");
	
	ParseBlocklist();
	
	LoadTranslations("calladmin_block.phrases");
	LoadTranslations("common.phrases");
	
}

void ParseBlocklist() {
	
	BuildPath(Path_SM, g_cConfigFile, sizeof(g_cConfigFile), "configs/calladmin_block_list.cfg");
	
	if (!FileExists(g_cConfigFile)) {
		
		File file = OpenFile(g_cConfigFile, "w");
		
		if (!file) {
			
			SetFailState("%s Error while trying to make the config file!", PREFIX);
			
		}
		
		file.WriteLine("// CallAdmin Blocklist - List of Steam IDs blocked from reporting.");
		file.WriteLine("");
		
		delete file;
		return;
		
	}
	
	File file = OpenFile(g_cConfigFile, "r");
	
	if (!file) {
		
		SetFailState("%s Error while attempting to parse the config file!", PREFIX);
		
	}
	
	char readBuffer[128];
	int len;
	
	while (!file.EndOfFile() && file.ReadLine(readBuffer, sizeof(readBuffer))) {
		
		if (readBuffer[0] == '/' || IsCharSpace(readBuffer[0])) {
			
			continue;
			
		}
		
		len = strlen(readBuffer);
		
		for (int i; i < len; i++) {
			
			if (readBuffer[i] == ' ' || readBuffer[i] == '/') {
				
				readBuffer[i] = '\0';
				len = strlen(readBuffer);
				
				break;
				
			}
			
		}
		
		if (!MatchRegex(g_rSteamIdRegex, readBuffer)) {
			
			SetFailState("%s Error while parsing the file, make sure it contains valid SteamIDs!", PREFIX, g_cConfigFile);
			
		}
		
	}
	
	delete file;
	
}

public void OnClientPostAdminCheck(int client) {
	
	File file = OpenFile(g_cConfigFile, "r");
	
	if (!file) {
		
		LogError("Error while trying to open the config file.");
		return;
		
	}
	
	char steamid[32];
	
	if (!GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid))) {
		
		LogError("Error while attempting to fetch client's Auth ID");
		return;
		
	}
	
	char readBuffer[128];
	int len;
	
	while (!file.EndOfFile() && file.ReadLine(readBuffer, sizeof(readBuffer))) {
		
		if (readBuffer[0] == '/' || IsCharSpace(readBuffer[0])) {
			
			continue;
			
		}
		
		len = strlen(readBuffer);
		
		for (int i; i < len; i++) {
			
			if (readBuffer[i] == ' ' || readBuffer[i] == '/') {
				
				readBuffer[i] = '\0';
				len = strlen(readBuffer);
				
				break;
				
			}
			
		}
		
		if (StrContains(readBuffer, steamid) != -1) {
			
			g_bIsClientBlocked[client] = true;
			return;
			
		}
		
	}
	
	delete file;
	
}

public Action CMD_Add(int client, int args) {
	
	if (!args) {
		
		CReplyToCommand(client, "%s Usage: sm_calladmin_block_add <user> | <STEAM_0:X:XXXXX>", PREFIX);
		return Plugin_Handled;
		
	}
	
	char arg1[32];
	GetCmdArgString(arg1, sizeof(arg1));
	
	char fileChar[32];
	bool isTarget;
	int target;
	
	if (MatchRegex(g_rSteamIdRegex, arg1)) {
		
		strcopy(fileChar, sizeof(fileChar), arg1);
		isTarget = false;
		
	}
	
	else {
		
		target = FindTarget(client, arg1, true, false);
		
		if (target == -1) {
			
			return Plugin_Handled;
			
		}
		
		else {
			
			if (!GetClientAuthId(target, AuthId_Steam2, fileChar, sizeof(fileChar))) {
				
				CReplyToCommand(client, "%s %t", PREFIX, "Error Get Auth ID");
				return Plugin_Handled;
				
			}
			
			isTarget = true;
			
		}
		
	}
	
	File file = OpenFile(g_cConfigFile, "r+");
	
	if (!file) {
		
		CReplyToCommand(client, "%s %t", PREFIX, "Error Opening File");
		return Plugin_Handled;
		
	}
	
	char readBuffer[128];
	int len;
	bool wasUserInBlocklist = false;
	
	while (!file.EndOfFile() && file.ReadLine(readBuffer, sizeof(readBuffer))) {
		
		if (readBuffer[0] == '/' || IsCharSpace(readBuffer[0])) {
			
			continue;
			
		}
		
		len = strlen(readBuffer);
		
		for (int i; i < len; i++) {
			
			if (readBuffer[i] == ' ' || readBuffer[i] == '/') {
				
				readBuffer[i] = '\0';
				len = strlen(readBuffer);
				
				break;
				
			}
			
		}
		
		if (StrContains(readBuffer, fileChar) != -1) {
			
			wasUserInBlocklist = true;
			break;
			
		}
		
	}
	
	if (!wasUserInBlocklist) {
		
		file.WriteLine(fileChar);
		
		if (isTarget) {
			
			char bufname[32];
			GetClientName(target, bufname, sizeof(bufname));
			CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Added Target", bufname);
			
		}
		
		else {
			
			CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Added");
			
		}
		
		g_bIsClientBlocked[target] = true;
		
	}
	
	else {
		
		if (isTarget) {
			
			char bufname[32];
			GetClientName(target, bufname, sizeof(bufname));
			CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Already Blocked Target", bufname);
			
		}
		
		else {
			
			CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Already Blocked");
			
		}
		
	}
	
	delete file;
	return Plugin_Handled;
	
}

public Action CMD_Remove(int client, int args) {
	
	if (!args) {
		
		CReplyToCommand(client, "%s Usage: sm_calladmin_block_remove <user> | <STEAM_0:X:XXXXX>", PREFIX);
		return Plugin_Handled;
		
	}
	
	char arg1[32];
	GetCmdArgString(arg1, sizeof(arg1));
	
	char fileChar[32];
	bool isTarget;
	int target;
	
	if (MatchRegex(g_rSteamIdRegex, arg1)) {
		
		strcopy(fileChar, sizeof(fileChar), arg1);
		isTarget = false;
		
	}
	
	else {
		
		target = FindTarget(client, arg1, true, false);
		
		if (target == -1) {
			
			return Plugin_Handled;
			
		}
		
		else {
			
			if (!GetClientAuthId(target, AuthId_Steam2, fileChar, sizeof(fileChar))) {
				
				CReplyToCommand(client, "%s %t", PREFIX, "Error Get Auth ID");
				return Plugin_Handled;
				
			}
			
			isTarget = true;
			
		}
		
	}
	
	File file1 = OpenFile(g_cConfigFile, "r");
	
	if (!file1) {
		
		CReplyToCommand(client, "%s %t", PREFIX, "Error Opening File");
		return Plugin_Handled;
		
	}
	
	char readBuffer[128];
	int len;
	
	ArrayList al = new ArrayList(ByteCountToCells(32));
	
	while (!file1.EndOfFile() && file1.ReadLine(readBuffer, sizeof(readBuffer))) {
		
		if (readBuffer[0] == '/' || IsCharSpace(readBuffer[0])) {
			
			continue;
			
		}
		
		len = strlen(readBuffer);
		
		for (int i; i < len; i++) {
			
			if (readBuffer[i] == ' ' || readBuffer[i] == '/') {
				
				readBuffer[i] = '\0';
				len = strlen(readBuffer);
				
				break;
				
			}
			
		}
		
		al.PushString(readBuffer);
		
	}
	
	delete file1;
	bool wasUserInBlocklist = false;
	
	for (int i = 0; i < al.Length; i++) {
		
		char buf[128];
		al.GetString(i, buf, sizeof(buf));
		
		if (StrContains(buf, fileChar) != -1) {
			
			al.Erase(i);
			wasUserInBlocklist = true;
			
		}
		
	}
	
	if (!wasUserInBlocklist) {
		
		if (isTarget) {
			
			char bufname[32];
			GetClientName(target, bufname, sizeof(bufname));
			CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Not In Blocklist Target", bufname);
			delete al;
			return Plugin_Handled;
			
		}
		
		else {
			
			CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Not In Blocklist");
			delete al;
			return Plugin_Handled;
			
		}
		
	}
	
	File file2 = OpenFile(g_cConfigFile, "w");
	
	if (!file2) {
		
		CReplyToCommand(client, "%s %t", PREFIX, "Error Opening File");
		return Plugin_Handled;
		
	}
	
	file2.WriteLine("// CallAdmin Blocklist - List of Steam IDs blocked from reporting.\n");
	file2.WriteLine("");
	
	
	for (int i = 0; i < al.Length; i++) {
		
		char buf[128];
		al.GetString(i, buf, sizeof(buf));
		
		file2.WriteString(buf, false);
		
	}
	
	if (isTarget) {
		
		char bufname[32];
		GetClientName(target, bufname, sizeof(bufname));
		CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Removed Target", bufname);
		
	}
	
	else {
		
		CReplyToCommand(client, "%s %t", PREFIX, "Steam ID Removed");
		
	}
	
	g_bIsClientBlocked[target] = false;
	
	delete file2;
	delete al;
	return Plugin_Handled;
	
}

public Action CMD_List(int client, int args) {
	
	Panel panel = new Panel();
	char panelTitle[64];
	Format(panelTitle, sizeof(panelTitle), "%t", "List of Steam IDs");
	
	panel.SetTitle(panelTitle);
	panel.DrawText(" ");
	
	File file = OpenFile(g_cConfigFile, "r");
	
	char readBuffer[128];
	int len;
	int j = 1;
	
	while (!file.EndOfFile() && file.ReadLine(readBuffer, sizeof(readBuffer))) {
		
		if (readBuffer[0] == '/' || IsCharSpace(readBuffer[0])) {
			
			continue;
			
		}
		
		len = strlen(readBuffer);
		
		for (int i; i < len; i++) {
			
			if (readBuffer[i] == ' ' || readBuffer[i] == '/') {
				
				readBuffer[i] = '\0';
				len = strlen(readBuffer);
				
				break;
				
			}
			
		}
		
		char panelText[32];
		Format(panelText, sizeof(panelText), "%i. %s", j, readBuffer);
		panel.DrawText(panelText);
		j++;
		
	}
	
	if (j == 1) {
		
		char noInfo[64];
		Format(noInfo, sizeof(noInfo), "%t", "No Information");
		panel.DrawText(noInfo);
		
	}
	
	panel.CurrentKey = 10;
	panel.DrawText(" ");
	panel.DrawItem("Exit");
	panel.Send(client, panelHandler, 20);
	
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
		
		LogError("Error while attempting to fetch client's Auth ID");
		return Plugin_Handled;
		
	}
	
	if (g_bIsClientBlocked[client]) {
		
		CReplyToCommand(client, "%s %t", PREFIX, "Not Allowed");
		return Plugin_Handled;
		
	}
	
	return Plugin_Continue;
	
}
