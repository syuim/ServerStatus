# -*- coding: utf-8 -*-
# Support Python Version 2.7 to 3.7
# Update by: https://github.com/CokeMine/ServerStatus-Hotaru

import socket
import time
import re
import os
import sys
import json
import subprocess
import threading
from collections import deque

SERVER = "rn.127315.xyz"
PORT = 35601
USER = "suyu"
PASSWORD = "68f30717b2bf0a5d33ed7a53c8f40bff"
INTERVAL = 1  # 更新间隔，单位：秒

# 节点标签，展示在前端展开行，可自定义；color 可选: blue/red/yellow/grey(默认)
TAGS = [
    {"text": "NODE"},
]

# Ping 目标（名称, 主机, 端口）：三网探测点；无 ping 命令时 TCP 回退用指定端口
PING_TARGETS = [
    ('CT', 'ct.127315.xyz', 80),  # 电信
    ('CU', 'cu.127315.xyz', 80),  # 联通
    ('CM', 'cm.127315.xyz', 80),  # 移动
]
PING_INTERVAL = 60   # 每轮 TCPing 间隔（秒）
PING_TIMEOUT = 3
PING_HISTORY = 20    # 保留的历史点数；custom 字段上限 512 字节，不宜增大


def get_os():
    try:
        with open('/etc/os-release', 'r') as f:
            for line in f:
                if line.startswith('PRETTY_NAME='):
                    return line.split('=', 1)[1].strip().strip('"')
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
    data = {'os': get_os(), 'cpu_model': cpu_model, 'cores': cores, 'tags': TAGS}
    if PING_TARGETS:
        data['ping'] = ping_collector.summary()
    return json.dumps(data)


class PingCollector(object):
    """后台线程定期 ping 各目标（ICMP 优先，无 ping 命令时回退 TCPing），保留最近 N 轮延迟（毫秒，-1 表示失败）"""

    def __init__(self):
        self.results = dict((name, deque(maxlen=PING_HISTORY)) for name, _, _ in PING_TARGETS)
        self.lock = threading.Lock()
        self._stop = threading.Event()
        self.use_icmp = self._icmp_available()
        if PING_TARGETS:
            t = threading.Thread(target=self._run)
            t.daemon = True
            t.start()

    @staticmethod
    def _icmp_available():
        try:
            subprocess.check_output(['ping', '-c', '1', '-W', '1', '127.0.0.1'], stderr=subprocess.STDOUT)
        except OSError:
            return False
        except Exception:
            pass
        return True

    @staticmethod
    def _icmp_ping(host):
        # Linux ping -W 单位为秒，macOS 为毫秒
        if sys.platform == 'darwin':
            cmd = ['ping', '-c', '1', '-W', str(PING_TIMEOUT * 1000), host]
        else:
            cmd = ['ping', '-c', '1', '-W', str(PING_TIMEOUT), host]
        try:
            out = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
            m = re.search(r'time[=<]\s*([\d.]+)\s*ms', out.decode('utf-8', 'ignore'))
            if m:
                return int(round(float(m.group(1))))
            return -1
        except Exception:
            return -1

    def _tcping(self, host, port):
        start = time.time()
        try:
            socket.create_connection((host, port), PING_TIMEOUT).close()
            return int(round((time.time() - start) * 1000))
        except Exception:
            return -1

    def _run(self):
        while not self._stop.is_set():
            for name, host, port in PING_TARGETS:
                if self.use_icmp:
                    ms = self._icmp_ping(host)
                else:
                    ms = self._tcping(host, port)
                with self.lock:
                    self.results[name].append(ms)
            self._stop.wait(PING_INTERVAL)

    def summary(self):
        with self.lock:
            return dict((name, list(values)) for name, values in self.results.items())


ping_collector = PingCollector()


def check_interface(net_name):
    net_name = net_name.strip()
    invalid_name = ['lo', 'tun', 'kube', 'docker', 'vmbr', 'br-', 'vnet', 'veth']
    return not any(name in net_name for name in invalid_name)


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
