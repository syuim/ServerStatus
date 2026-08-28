#ifndef MAIN_H
#define MAIN_H

#include <stdint.h>
#include "server.h"

class CConfig
{
public:
	bool m_Verbose;
	char m_aConfigFile[1024];
	char m_aWebDir[1024];
	char m_aTemplateFile[1024];
	char m_aJSONFile[1024];
	char m_aBindAddr[256];
	int m_Port;
	char m_aKey[128]; // 全局密钥：客户端可用该密钥代替节点密码认证

	CConfig();
};

#define PING_HISTORY_MAX 1440

class CMain
{
public:
	// 每节点每探测线一条，key 为 "节点名:线名"（如 "RN:CT"），1440 点 = 24h @ 60s
	struct CPingLine
	{
		char m_aName[64];
		int m_Count;
		int aT[PING_HISTORY_MAX];
		short aV[PING_HISTORY_MAX];
	};

	CConfig m_Config;
	CServer m_Server;

	CPingLine *m_apPingLines;
	int m_PingLineCount;
	int m_PingLineAlloc;

	struct CClient
	{
		bool m_Active;
		bool m_Disabled;
		bool m_Connected;
		int m_ClientNetID;
		int m_ClientNetType;
		char m_aUsername[128];
		char m_aName[128];
		char m_aType[128];
		char m_aHost[128];
		char m_aLocation[128];
		char m_aRegion[128];
		char m_aPassword[128];
		char m_aIP[64]; // 客户端连接 IP，写入 stats.json 供前端 GeoIP 定位

		int64 m_TimeConnected;
		int64 m_LastUpdate;

		struct CStats
		{
			bool m_Online4;
			bool m_Online6;
			int64_t m_Uptime;
			double m_Load;
			int64_t m_NetworkRx;
			int64_t m_NetworkTx;
			int64_t m_NetworkIN;
			int64_t m_NetworkOUT;
			int64_t m_MemTotal;
			int64_t m_MemUsed;
			int64_t m_SwapTotal;
			int64_t m_SwapUsed;
			int64_t m_HDDTotal;
			int64_t m_HDDUsed;
			double m_CPU;
			char m_aCustom[512];
			// Options
			bool m_Pong;
		} m_Stats;
	} m_aClients[NET_MAX_CLIENTS];

	struct CJSONUpdateThreadData
	{
		CClient *pClients;
		CConfig *pConfig;
		volatile short m_ReloadRequired;
		CMain *pMain;
	} m_JSONUpdateThreadData;

	static void JSONUpdateThread(void *pUser);
	void AppendPing(const char *pNode, const char *pLine, int64 t, int v);
	void WriteHistoryFile(const CConfig *pConfig);
	void LoadHistoryFile(const CConfig *pConfig);
	void AddConfigClient(const char *pUsername, const char *pPassword);
public:
	CMain(CConfig Config);

	void OnNewClient(int ClienNettID, int ClientID);
	void OnDelClient(int ClientNetID);
	int HandleMessage(int ClientNetID, char *pMessage);
	int ReadConfig();
	int Run();

	CClient *Client(int ClientID) { return &m_aClients[ClientID]; }
	CClient *ClientNet(int ClientNetID);
	const CConfig *Config() const { return &m_Config; }
	int ClientNetToClient(int ClientNetID);
};


#endif
