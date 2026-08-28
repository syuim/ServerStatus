# -*- coding: utf-8 -*-
# Support Python Version 2.7 to 3.7
# Update by: https://github.com/CokeMine/ServerStatus-Hotaru

import socket
import time
import re
import os
import sys
import json
import signal
import calendar
import subprocess
import threading
from collections import deque
from datetime import datetime

SERVER = "rn.127315.xyz"
PORT = 35601
USER = "suyu"
PASSWORD = "68f30717b2bf0a5d33ed7a53c8f40bff"
INTERVAL = 1  # 更新间隔，单位：秒

# 节点标签，展示在前端展开行，可自定义；color 可选: blue/red/yellow/grey(默认)
TAGS = [
    {"text": "NODE"},
]

# Ping 目标（名称, 主机, 端口, 地址族）：三网双栈 + 公共 DNS 单栈探测；无对应出站时超时
PING_TARGETS = [
    ('CT', 'zj-ct-dualstack.ip.zstaticcdn.com', 80, socket.AF_INET),
    ('CT6', 'zj-ct-dualstack.ip.zstaticcdn.com', 80, socket.AF_INET6),
    ('CU', 'zj-cu-dualstack.ip.zstaticcdn.com', 80, socket.AF_INET),
    ('CU6', 'zj-cu-dualstack.ip.zstaticcdn.com', 80, socket.AF_INET6),
    ('CM', 'zj-cm-dualstack.ip.zstaticcdn.com', 80, socket.AF_INET),
    ('CM6', 'zj-cm-dualstack.ip.zstaticcdn.com', 80, socket.AF_INET6),
    ('CF', '1.1.1.1', 443, socket.AF_INET),
    ('GO', '8.8.8.8', 443, socket.AF_INET),
]
PING_INTERVAL = 60   # 每轮 TCPing 间隔（秒）
PING_TIMEOUT = 3
PING_HISTORY = 15    # 保留的历史点数；custom 字段上限 512 字节，含时间戳后不宜增大
LOCATION_REFRESH = 21600  # 位置信息刷新间隔（秒），6 小时

# 周期流量每月几号重置（1-28 安全，大于当月天数时按当月最后一天）；总流量永久累计
TRAFFIC_RESET_DAY = 1
# 周期流量配额（字节，0=不限制），前端按上下行总和展示进度条
TRAFFIC_QUOTA = 0
TRAFFIC_STATE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'traffic.json')

_location = None
_location_ts = 0


def get_location():
    """按出口 IP 查询国家代码（如 US），结果缓存 LOCATION_REFRESH 秒"""
    global _location, _location_ts
    now = time.time()
    if _location is not None and now - _location_ts < LOCATION_REFRESH:
        return _location
    _location = ''
    _location_ts = now
    try:
        import urllib.request
        req = urllib.request.Request(
            'http://ip-api.com/json/?fields=status,countryCode',
            headers={'User-Agent': 'curl/7.0'})
        data = json.load(urllib.request.urlopen(req, timeout=8))
        if data.get('status') == 'success' and data.get('countryCode'):
            _location = data['countryCode']
            return _location
    except Exception:
        pass
    try:
        import urllib.request
        data = json.load(urllib.request.urlopen('https://ipinfo.io/json', timeout=8))
        if data.get('country'):
            _location = data['country']
    except Exception:
        pass
    return _location


def get_os():
    try:
        with open('/etc/os-release', 'r') as f:
            for line in f:
                if line.startswith('PRETTY_NAME='):
                    name = line.split('=', 1)[1].strip().strip('"')
                    # 只保留发行版名第一个词："Debian GNU/Linux 12 (bookworm)" -> "Debian"
                    return name.split()[0] if name else ''
    except IOError:
        pass
    return ''


def get_custom():
    cpu_model = ''
    cores = 0
    try:
        with open('/proc/cpuinfo', 'r') as f:
            for line in f:
                if line.startswith('model name') and not cpu_model:
                    cpu_model = line.split(':')[1].strip()
                elif line.startswith('processor'):
                    cores += 1
    except IOError:
        pass
    data = {'os': get_os(), 'cpu_model': cpu_model, 'cores': cores, 'tags': TAGS, 'loc': get_location()}
    data['traffic'] = traffic_tracker.summary()
    if PING_TARGETS:
        data['ping'] = ping_collector.summary()
        # custom 字段服务端上限 512 字节，超限时缩减各线历史点数
        encoded = json.dumps(data)
        for keep in (12, 10, 8, 6):
            if len(encoded) <= 500:
                break
            ping = data['ping']
            for k in list(ping.keys()):
                if k in ('t', 'iv'):
                    continue
                ping[k] = ping[k][-keep:]
            encoded = json.dumps(data)
        return encoded
    return json.dumps(data)


class PingCollector(object):
    """后台线程定期 TCPing 各目标（TCP 连接耗时毫秒，-1 表示失败），保留最近 N 轮延迟"""

    def __init__(self):
        self.results = dict((name, deque(maxlen=PING_HISTORY)) for name, _, _, _ in PING_TARGETS)
        self.last_ts = 0
        self.lock = threading.Lock()
        self._stop = threading.Event()
        if PING_TARGETS:
            t = threading.Thread(target=self._run)
            t.daemon = True
            t.start()

    def _tcping(self, host, port, family):
        start = time.time()
        try:
            sock = socket.socket(family, socket.SOCK_STREAM)
            sock.settimeout(PING_TIMEOUT)
            sock.connect((host, port))
            sock.close()
            return int(round((time.time() - start) * 1000))
        except Exception:
            return -1

    def _run(self):
        while not self._stop.is_set():
            ts = int(time.time())
            for name, host, port, family in PING_TARGETS:
                ms = self._tcping(host, port, family)
                with self.lock:
                    self.results[name].append(ms)
                    self.last_ts = ts
            self._stop.wait(PING_INTERVAL)

    def summary(self):
        with self.lock:
            # 服务端持久化完整历史，这里只上报每线最新一点 + 时间戳
            data = {}
            for name, values in self.results.items():
                data[name] = [values[-1]] if values else []
            data['t'] = self.last_ts or int(time.time())
            data['iv'] = PING_INTERVAL
            return data


ping_collector = PingCollector()


def check_interface(net_name):
    net_name = net_name.strip()
    invalid_name = ['lo', 'tun', 'kube', 'docker', 'vmbr', 'br-', 'vnet', 'veth']
    return not any(name in net_name for name in invalid_name)


class TrafficTracker(object):
    """流量统计：周期流量按 TRAFFIC_RESET_DAY 每月重置（差值累计），
    总流量优先取 vnstat（跨机器重启准确），无 vnstat 时回退差值累计"""

    _net_re = re.compile(r'([^\s]+):[\s]*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)')

    def __init__(self, state_file=TRAFFIC_STATE_FILE, reset_day=TRAFFIC_RESET_DAY):
        self.state_file = state_file
        self.reset_day = reset_day
        self.state = {'total_rx': 0, 'total_tx': 0, 'period_rx': 0, 'period_tx': 0, 'period_start': ''}
        self.last_rx = None
        self.last_tx = None
        self._last_save = 0
        # vnstat 数据缓存：基值 + 基准网卡计数，60s 刷新一次
        self._vnstat_rx = None
        self._vnstat_tx = None
        self._vnstat_base_rx = 0
        self._vnstat_base_tx = 0
        self._vnstat_ts = 0
        self._load()

    def _load(self):
        try:
            with open(self.state_file) as f:
                self.state.update(json.load(f))
        except Exception:
            pass

    def _save(self):
        try:
            tmp = self.state_file + '.tmp'
            with open(tmp, 'w') as f:
                json.dump(self.state, f)
            os.rename(tmp, self.state_file)
        except Exception:
            pass

    def _vnstat_total(self):
        # 读取 vnstat 至今总流量 (rx, tx) 字节；vnstat 未装/无数据时返回 None
        try:
            out = os.popen('vnstat --oneline b').readline()
            if not out or 'Not enough data available yet' in out:
                return None
            v_data = out.split(';')
            if len(v_data) > 10:
                return int(v_data[8]), int(v_data[9])
        except Exception:
            pass
        return None

    def _read_counters(self):
        rx = 0
        tx = 0
        try:
            with open('/proc/net/dev') as f:
                for line in f.readlines():
                    info = self._net_re.findall(line)
                    if info and check_interface(info[0][0]):
                        rx += int(info[0][1])
                        tx += int(info[0][9])
        except IOError:
            pass
        return rx, tx

    def _period_start(self, now):
        # 当前周期起点：最近一个 reset_day 且不晚于 now；大于当月天数时按当月最后一天
        try:
            start = datetime(now.year, now.month, self.reset_day)
        except ValueError:
            start = datetime(now.year, now.month, calendar.monthrange(now.year, now.month)[1])
        if start > now:
            prev_month = now.month - 1 or 12
            prev_year = now.year - (1 if now.month == 1 else 0)
            try:
                start = datetime(prev_year, prev_month, self.reset_day)
            except ValueError:
                start = datetime(prev_year, prev_month, calendar.monthrange(prev_year, prev_month)[1])
        return start.strftime('%Y-%m-%d')

    def update(self):
        rx, tx = self._read_counters()
        now = datetime.now()
        if self.last_rx is not None:
            if rx >= self.last_rx and tx >= self.last_tx:
                drx, dtx = rx - self.last_rx, tx - self.last_tx
            else:
                # 进程运行中网卡计数重置（换网卡等）：从新基线继续
                drx, dtx = 0, 0
        else:
            saved_rx = self.state.get('last_rx')
            saved_tx = self.state.get('last_tx')
            if saved_rx is not None and rx >= saved_rx and tx >= saved_tx:
                # 进程重启但网卡计数连续（机器未重启）：补计离线期间的流量
                drx, dtx = rx - saved_rx, tx - saved_tx
            else:
                # 首次部署或机器重启（网卡计数归零）：只建基线，不计历史流量
                drx, dtx = 0, 0
        self.last_rx, self.last_tx = rx, tx
        pstart = self._period_start(now)
        if pstart != self.state.get('period_start'):
            self.state['period_start'] = pstart
            self.state['period_rx'] = 0
            self.state['period_tx'] = 0
        self.state['total_rx'] += drx
        self.state['total_tx'] += dtx
        self.state['period_rx'] += drx
        self.state['period_tx'] += dtx
        # 总流量优先用 vnstat：基值 60s 刷新一次，间隙用网卡差值平滑补足；
        # 网卡计数回退（机器重启）时立即刷新
        if time.time() - self._vnstat_ts >= 60 or (
                self._vnstat_rx is not None and (rx < self._vnstat_base_rx or tx < self._vnstat_base_tx)):
            vn = self._vnstat_total()
            if vn is not None:
                self._vnstat_ts = time.time()
                self._vnstat_rx, self._vnstat_tx = vn
                self._vnstat_base_rx, self._vnstat_base_tx = rx, tx
        if self._vnstat_rx is not None:
            if rx < self._vnstat_base_rx or tx < self._vnstat_base_tx:
                # 机器重启且 vnstat 刷新失败（如无数据）：按当前计数重建基准
                self._vnstat_base_rx, self._vnstat_base_tx = rx, tx
                self.state['total_rx'] = self._vnstat_rx
                self.state['total_tx'] = self._vnstat_tx
            else:
                self.state['total_rx'] = self._vnstat_rx + (rx - self._vnstat_base_rx)
                self.state['total_tx'] = self._vnstat_tx + (tx - self._vnstat_base_tx)
        # 记录最近一次网卡计数，进程重启后可据此补计间隙流量
        self.state['last_rx'] = rx
        self.state['last_tx'] = tx
        if time.time() - self._last_save >= 3:
            self._save()
            self._last_save = time.time()
        return self.state

    def summary(self):
        self.update()
        return {
            'pr': int(self.state['period_rx']),
            'pt': int(self.state['period_tx']),
            'tr': int(self.state['total_rx']),
            'tt': int(self.state['total_tx']),
            'rd': self.reset_day,
            'q': TRAFFIC_QUOTA,
        }


traffic_tracker = TrafficTracker()


def get_uptime():
    with open('/proc/uptime', 'r') as f:
        uptime = f.readline().split('.')
    return int(uptime[0])


def get_memory():
    re_parser = re.compile(r'(\S*):\s*(\d*)\s*kB')
    result = dict()
    for line in open('/proc/meminfo'):
        match = re_parser.match(line)
        if match:
            result[match.group(1)] = int(match.group(2))

    mem_total = float(result['MemTotal'])
    mem_free = float(result['MemFree'])
    buffers = float(result['Buffers'])
    cached = float(result['Cached'])
    mem_used = mem_total - (mem_free + buffers + cached)
    swap_total = float(result['SwapTotal'])
    swap_free = float(result['SwapFree'])
    return int(mem_total), int(mem_used), int(swap_total), int(swap_free)


def get_hdd():
    p = subprocess.check_output(
        ['df', '-Tlm', '--total', '-t', 'ext4', '-t', 'ext3', '-t', 'ext2', '-t', 'reiserfs', '-t', 'jfs', '-t', 'ntfs',
         '-t', 'fat32', '-t', 'btrfs', '-t', 'fuseblk', '-t', 'zfs', '-t', 'simfs', '-t', 'xfs']).decode('utf-8')
    total = p.splitlines()[-1]
    used = total.split()[3]
    size = total.split()[2]
    return int(size), int(used)


def get_load():
    return round(os.getloadavg()[0], 1)


def get_cpu_time():
    with open('/proc/stat', 'r') as stat_file:
        time_list = stat_file.readline().split()[1:]
    time_list = list(map(int, time_list))
    return sum(time_list), time_list[3]


def get_cpu():
    old_total, old_idle = get_cpu_time()
    time.sleep(INTERVAL)
    total, idle = get_cpu_time()
    return round(100 - float(idle - old_idle) / (total - old_total) * 100.00, 1)


def get_traffic_vnstat():
    vnstat = os.popen('vnstat --oneline b').readline()
    if "Not enough data available yet" in vnstat:
        return 0, 0
    v_data = vnstat.split(';')
    net_in = int(v_data[8])
    net_out = int(v_data[9])
    return net_in, net_out


class Network:
    def __init__(self):
        self.rx = deque(maxlen=10)
        self.tx = deque(maxlen=10)
        self._get_traffic()

    def _get_traffic(self):
        net_in = 0
        net_out = 0
        re_parser = re.compile(r'([^\s]+):[\s]*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+('
                               r'\d+)\s+(\d+)\s+(\d+)')
        with open('/proc/net/dev') as f:
            for line in f.readlines():
                net_info = re_parser.findall(line)
                if net_info:
                    if check_interface(net_info[0][0]):
                        net_in += int(net_info[0][1])
                        net_out += int(net_info[0][9])
        self.rx.append(net_in)
        self.tx.append(net_out)

    def get_speed(self):
        self._get_traffic()
        avg_rx = 0
        avg_tx = 0
        queue_len = len(self.rx)
        for x in range(queue_len - 1):
            avg_rx += self.rx[x + 1] - self.rx[x]
            avg_tx += self.tx[x + 1] - self.tx[x]
        avg_rx = int(avg_rx / queue_len / INTERVAL)
        avg_tx = int(avg_tx / queue_len / INTERVAL)
        return avg_rx, avg_tx

    def get_traffic(self):
        queue_len = len(self.rx)
        return self.rx[queue_len - 1], self.tx[queue_len - 1]


def get_network(ip_version):
    if ip_version == 4:
        host = 'ipv4.google.com'
    elif ip_version == 6:
        host = 'ipv6.google.com'
    else:
        return False
    try:
        socket.create_connection((host, 80), 2).close()
        return True
    except Exception:
        return False


if __name__ == '__main__':
    socket.setdefaulttimeout(30)

    def save_on_exit(signum, frame):
        # systemctl stop / 手动重启时把最新计数落盘，重启后可补计间隙流量
        try:
            traffic_tracker._save()
        except Exception:
            pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, save_on_exit)
    signal.signal(signal.SIGINT, save_on_exit)
    while True:
        try:
            print('Connecting...')
            s = socket.create_connection((SERVER, PORT))
            data = s.recv(1024).decode()
            if data.find('Authentication required') > -1:
                s.send((USER + ':' + PASSWORD + '\n').encode('utf-8'))
                data = s.recv(1024).decode()
                if data.find('Authentication successful') < 0:
                    print(data)
                    raise socket.error
            else:
                print(data)
                raise socket.error

            print(data)
            if data.find('You are connecting via') < 0:
                data = s.recv(1024).decode()
                print(data)

            timer = 0
            check_ip = 0
            if data.find('IPv4') > -1:
                check_ip = 6
            elif data.find('IPv6') > -1:
                check_ip = 4
            else:
                print(data)
                raise socket.error

            traffic = Network()
            while True:
                CPU = get_cpu()
                NetRx, NetTx = traffic.get_speed()
                NET_IN, NET_OUT = traffic.get_traffic()
                Uptime = get_uptime()
                Load = get_load()
                MemoryTotal, MemoryUsed, SwapTotal, SwapFree = get_memory()
                HDDTotal, HDDUsed = get_hdd()

                array = {}
                if not timer:
                    array['online' + str(check_ip)] = get_network(check_ip)
                    timer = 150
                else:
                    timer -= 1 * INTERVAL

                array['uptime'] = Uptime
                array['load'] = Load
                array['memory_total'] = MemoryTotal
                array['memory_used'] = MemoryUsed
                array['swap_total'] = SwapTotal
                array['swap_used'] = SwapTotal - SwapFree
                array['hdd_total'] = HDDTotal
                array['hdd_used'] = HDDUsed
                array['cpu'] = CPU
                array['network_rx'] = NetRx
                array['network_tx'] = NetTx
                array['network_in'] = NET_IN
                array['network_out'] = NET_OUT
                array['custom'] = get_custom()
                s.send(("update " + json.dumps(array) + '\n').encode('utf-8'))
        except KeyboardInterrupt:
            raise
        except socket.error:
            print('Disconnected...')
            # keep on trying after a disconnect
            if 's' in locals().keys():
                del s
            time.sleep(3)
        except Exception as e:
            print('Caught Exception:', e)
            if 's' in locals().keys():
                del s
            time.sleep(3)
