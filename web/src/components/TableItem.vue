<template>
  <tr class="tableRow" @click="collapsed = !collapsed">
    <td>
      <div class="ui progress" :class="{'success': getStatus, 'error': !getStatus}">
        <div class="bar bar--solid" style="width: 100%"><span> {{ getStatus ? '运行中' : '维护中' }} </span>
        </div>
      </div>
    </td>
    <td>{{ server.name }}</td>
    <td>{{ osName }}</td>
    <td>{{ locationName }}</td>
    <td>{{ server.uptime || '–' }}</td>
    <td>{{ getStatus ? server.load : '-' }}</td>
    <td>{{
        getStatus ? `${tableRowByteConvert(server.network_rx)} | ${tableRowByteConvert(server.network_tx)}` : '–'
      }}
    </td>
    <td>
      <template v-if="getStatus && trafficQuota">
        <div class="ui progress" :class="trafficQuotaState">
          <div class="bar" :style="{'width': trafficQuotaPct + '%'}">{{ trafficQuotaPct }}%</div>
        </div>
      </template>
      <template v-else>{{
          getStatus ? `${tableRowByteConvert(server.network_in)} | ${tableRowByteConvert(server.network_out)}` : '–'
        }}
      </template>
    </td>
    <td>
      <div class="ui progress" :class="getProcessBarStatus(getCpuStatus)">
        <div class="bar" :style="{'width': `${getCpuStatus.toString()}%`}">
          {{ getStatus ? `${getCpuStatus.toString()}%` : '维护中' }}
        </div>
      </div>
    </td>
    <td>
      <div class="ui progress" :class="getProcessBarStatus(getRAMStatus)">
        <div class="bar" :style="{'width': `${getRAMStatus.toString()}%`}">
          {{ getStatus ? `${getRAMStatus.toString()}%` : '维护中' }}
        </div>
      </div>
    </td>
    <td>
      <div class="ui progress" :class="getProcessBarStatus(getHDDStatus)">
        <div class="bar" :style="{'width': `${getHDDStatus.toString()}%`}">
          {{ getStatus ? `${getHDDStatus.toString()}%` : '维护中' }}
        </div>
      </div>
    </td>
  </tr>
  <tr class="expandRow">
    <td colspan="11">
      <div class="expand-inner" :class="{collapsed}" :style="{'max-height': getStatus ? '' : '0'}">
        <div id="expand_cpu">CPU: {{ getStatus ? cpuModel : '–' }}</div>
        <div id="expand_mem">内存信息: {{
            getStatus ? `${expandRowByteConvert(server.memory_used * 1024)} / ${expandRowByteConvert(server.memory_total * 1024)}` : '–'
          }}
        </div>
        <div id="expand_swap">交换分区: {{
            getStatus ? `${expandRowByteConvert(server.swap_used * 1024)} / ${expandRowByteConvert(server.swap_total * 1024)}` : '–'
          }}
        </div>
        <div id="expand_hdd">硬盘信息: {{
            getStatus ? `${expandRowByteConvert(server.hdd_used * 1024 * 1024)} / ${expandRowByteConvert(server.hdd_total * 1024 * 1024)}` : '–'
          }}
        </div>
        <div id="expand_traffic_period">流量: {{ getStatus ? (trafficQuota ? trafficQuotaTextPct : trafficPeriodText) : '–' }}</div>
        <div class="tag-line" v-if="tags.length">
          <span v-for="t in tags" :key="t.text" class="tag" :class="t.color ? `tag--${t.color}` : ''">{{ t.text }}</span>
        </div>
        <div class="ping-panel" v-if="getStatus && !collapsed && currentSeries" @click.stop>
          <div class="ping-head">
            <div class="ping-tabs">
              <button v-for="s in pingSeries" :key="s.name" type="button"
                      class="ping-tab" :class="{active: s.name === activePing}"
                      @click="activePing = s.name">{{ s.name }}
              </button>
            </div>
            <div class="ping-stats">
              <span class="ping-stat ping-stat--avg">{{ activeAvgText }}</span>
              <span class="ping-stat ping-stat--loss">{{ activeLossText }}</span>
            </div>
          </div>
          <div class="ping-chart-wrap">
            <ping-chart :values="currentSeries.values" :start-ts="currentSeries.startTs" :iv="currentSeries.iv"/>
          </div>
        </div>
      </div>
    </td>
  </tr>
</template>

<script lang="ts">
import { defineComponent, ref, computed, watch, inject, PropType } from 'vue';
import useStatus from './useStatus';
import PingChart from './PingChart.vue';
import { StatusItem } from '@/types';

interface CustomData {
  os?: string;
  cpu_model?: string;
  cores?: number;
  loc?: string;
  tags?: Array<{ text?: string; color?: string }>;
  ping?: Record<string, number[]>;
  traffic?: { pr?: number; pt?: number; tr?: number; tt?: number; rd?: number; q?: number };
}

// tab 显示顺序：默认展示 CU，CT 移到 CM 后
const PING_ORDER = ['CU', 'CU6', 'CM', 'CM6', 'CT', 'CT6', 'CF', 'GO'];

export default defineComponent({
  name: 'TableItem',
  props: {
    server: {
      type: Object as PropType<StatusItem>,
      default: () => ({})
    },
    history: {
      type: Object as PropType<Record<string, {t: number; iv: number; v: number[]}>>,
      default: () => ({})
    }
  },
  setup(props) {
    const collapsed = ref(true);
    // 首次展开行时通知 App 拉取延迟历史，图表数据懒加载
    const ensureHistory = inject<() => void>('ensureHistory');
    watch(collapsed, (v) => {
      if (!v && ensureHistory) ensureHistory();
    });
    const utils = useStatus(props);
    const customData = computed<CustomData | null>(() => {
      const raw = props.server.custom;
      if (!raw) return null;
      try {
        return JSON.parse(raw);
      } catch {
        return null;
      }
    });
    const cpuModel = computed(() => {
      const d = customData.value;
      if (!d || !d.cpu_model) return '–';
      const model = d.cpu_model
        .replace(/\s*CPU\s*@\s*[\d.]+GHz\s*/i, '')
        .replace(/\s*\d+\s*[-–]?\s*Core\s*Processor$/i, '')
        .replace(/^Intel\(R\)\s*/i, '')
        .replace(/\s*CPU\s*$/i, '')
        .trim();
      const cores = d.cores ? ` ${d.cores} vCore${d.cores > 1 ? 's' : ''}` : '';
      return `${model}${cores}`;
    });
    const osName = computed(() => {
      const d = customData.value;
      return d && d.os ? d.os : '–';
    });
    const tags = computed(() => {
      const d = customData.value;
      if (!d || !Array.isArray(d.tags)) return [];
      return d.tags.filter(t => t && t.text).map(t => ({ text: t.text, color: t.color || '' }));
    });
    const locationName = computed(() => {
      const d = customData.value;
      return (d && d.loc) ? d.loc : (props.server.location || '–');
    });
    const traffic = computed(() => {
      const d = customData.value;
      return d && d.traffic ? d.traffic : null;
    });
    const trafficQuota = computed(() => {
      const t = traffic.value;
      return t && t.q && t.q > 0 ? t.q : 0;
    });
    const trafficSum = computed(() => {
      const t = traffic.value;
      return t ? (t.pr || 0) + (t.pt || 0) : 0;
    });
    const trafficQuotaPct = computed(() => {
      const q = trafficQuota.value;
      if (!q) return 0;
      return Math.min(100, Math.round(trafficSum.value / q * 100));
    });
    const trafficQuotaState = computed(() => {
      const p = trafficQuotaPct.value;
      return p > 90 ? 'error' : p > 70 ? 'warning' : 'success';
    });
    const trafficQuotaText = computed(() => {
      if (!trafficQuota.value) return '';
      const fmt = utils.expandRowByteConvert.value;
      return `${fmt(trafficSum.value)} / ${fmt(trafficQuota.value)}`;
    });
    const trafficQuotaTextPct = computed(() => {
      if (!trafficQuota.value) return '';
      return `${trafficQuotaPct.value}% · ${trafficQuotaText.value}`;
    });
    const trafficPeriodText = computed(() => {
      const t = traffic.value;
      if (!t) return '–';
      const fmt = utils.expandRowByteConvert.value;
      return `↑ ${fmt(t.pr || 0)} ↓ ${fmt(t.pt || 0)}`;
    });
    const pingSeries = computed(() => {
      const d = customData.value;
      if (!d || !d.ping) return [];
      const raw = d.ping as Record<string, unknown>;
      const t = typeof raw.t === 'number' && raw.t > 0 ? raw.t : 0;
      const iv = typeof raw.iv === 'number' && raw.iv > 0 ? raw.iv : 60;
      return Object.keys(raw)
        .filter(k => k !== 't' && k !== 'iv')
        .filter(k => Array.isArray(raw[k]) && (raw[k] as number[]).length)
        .map(name => ({name, values: raw[name] as number[], startTs: t, iv}))
        .sort((a, b) => {
          const ia = PING_ORDER.indexOf(a.name);
          const ib = PING_ORDER.indexOf(b.name);
          return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
        });
    });
    const activePing = ref('');
    watch(
      () => pingSeries.value.map(s => s.name).join(','),
      (names) => {
        if (!names) return;
        const list = names.split(',');
        if (!list.includes(activePing.value)) activePing.value = list[0];
      },
      { immediate: true }
    );
    const historySeries = computed(() => {
      const h = props.history;
      if (!h || !props.server.name) return [];
      const names = pingSeries.value.map(s => s.name);
      if (!names.length) return [];
      const out: Array<{ name: string; values: number[]; startTs: number; iv: number }> = [];
      for (const name of names) {
        const entry = h[`${props.server.name}:${name}`];
        if (entry && Array.isArray(entry.v) && entry.v.length) {
          out.push({ name, values: entry.v, startTs: entry.t || 0, iv: entry.iv || 60 });
        }
      }
      return out;
    });
    const currentSeries = computed(() => {
      const list = historySeries.value.length ? historySeries.value : pingSeries.value;
      if (!list.length) return null;
      return list.find(s => s.name === activePing.value) || list[0];
    });
    const validValues = computed(() => {
      const s = currentSeries.value;
      if (!s) return [];
      return s.values.filter(v => v >= 0);
    });
    const activeAvg = computed(() => {
      const vals = validValues.value;
      if (!vals.length) return '–';
      return Math.round(vals.reduce((a, b) => a + b, 0) / vals.length);
    });
    const activeLoss = computed(() => {
      const s = currentSeries.value;
      if (!s || !s.values.length) return '–';
      return Math.round((s.values.length - validValues.value.length) / s.values.length * 1000) / 10;
    });
    const activeAvgText = computed(() => activeAvg.value === '–' ? '–' : `${activeAvg.value}ms`);
    const activeLossText = computed(() => activeLoss.value === '–' ? '–' : `${activeLoss.value}%`);
    return {
      collapsed,
      locationName,
      cpuModel,
      osName,
      tags,
      trafficPeriodText,
      trafficQuota,
      trafficQuotaPct,
      trafficQuotaState,
      trafficQuotaTextPct,
      pingSeries,
      activePing,
      currentSeries,
      activeAvgText,
      activeLossText,
      ...utils
    };
  },
  components: {
    PingChart
  }
});
</script>

<style scoped>

tr.tableRow {
  background-color: rgba(249, 249, 249, .8);
  vertical-align: middle;
}

tr.tableRow td {
  padding: .3em .5em !important;
}

tr.tableRow:hover {
  background-color: rgba(243, 243, 243, .9);
}

tr.expandRow td {
  padding: .25em .5em !important;
}

.expand-inner {
  overflow: hidden;
  transition: max-height .5s ease;
  max-height: 34em;
  text-align: center;
}

.expand-inner.collapsed {
  max-height: 0;
}

.tag-line {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: center;
  gap: .35em;
  margin-top: .35em;
}

.tag {
  display: inline-block;
  vertical-align: baseline;
  background-color: #e8e8e8;
  color: #616366;
  font-weight: bold;
  font-size: .78571429rem;
  line-height: 1;
  padding: .5833em .833em;
  border-radius: .28571429rem;
  word-break: keep-all;
  white-space: nowrap;
}

.tag--blue {
  background-color: #2185d0;
  color: #fff;
}

.tag--red {
  background-color: #db2828;
  color: #fff;
}

.tag--yellow {
  background-color: #fbbd08;
  color: #fff;
}

.ping-panel {
  margin: .8em 0 .2em;
  padding: .9em 1.1em 1em;
  text-align: left;
  background: #f5f5f5;
  border-radius: var(--hotaru-radius);
  border: none;
  font-weight: 500;
  color: var(--hotaru-text);
}

.ping-head {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: .4em;
  margin-bottom: .7em;
}

.ping-tabs {
  display: inline-flex;
  flex-wrap: wrap;
  gap: .35em;
  align-items: center;
}

.ping-tab {
  border: none;
  border-radius: 6px;
  background: transparent;
  color: var(--hotaru-text);
  font-size: .82rem;
  font-weight: 700;
  line-height: 1.2;
  padding: .35em .85em;
  cursor: pointer;
  transition: background .15s ease, color .15s ease;
}

.ping-tab:hover {
  background: rgba(33, 186, 69, .08);
  color: var(--hotaru-text);
}

.ping-tab.active,
.ping-tab.active:hover {
  background: var(--hotaru-status-ok);
  color: #fff;
}

.ping-stats {
  display: inline-flex;
  flex-wrap: wrap;
  gap: .4em;
  align-items: center;
  margin-left: auto;
}

.ping-stat {
  display: inline-flex;
  align-items: baseline;
  min-width: 3.6em;
  justify-content: center;
  background-color: rgba(0, 0, 0, .05);
  color: var(--hotaru-text);
  font-size: .78571429rem;
  line-height: 1;
  font-weight: 700;
  padding: .5em .833em;
  border: 0;
  border-radius: .28571429rem;
  box-shadow: inset 0 1px rgba(255, 255, 255, .55);
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}

div.progress {
  display: inline-block;
  overflow: hidden;
  height: 22px;
  width: 100%;
  min-width: 40px;
  max-width: 120px;
  border-radius: 6px;
  background: rgba(0, 0, 0, .1);
  margin-bottom: 0 !important;
}

div.progress div.bar {
  height: 22px;
  border-radius: 6px;
  font-size: .85rem;
  line-height: 22px;
  /* 深色文字：进度不满时溢出到白色背景部分依然可读 */
  color: rgba(0, 0, 0, .62);
  text-align: left;
  padding-left: .4em;
  white-space: nowrap;
  transition: width .1s ease, background-color .1s ease;
}

div.progress div.bar.bar--solid {
  color: #fff;
  text-align: center;
  padding-left: 0;
}

div.progress.success div.bar {
  background: var(--hotaru-status-ok);
}

div.progress.warning div.bar {
  background: var(--hotaru-status-warn);
}

div.progress.error div.bar {
  background: var(--hotaru-status-bad);
}

tr td {
  color: #616366;
  font-weight: bold;
  border: none !important;
  white-space: nowrap;
}

/* 移动端：展开行 CPU 文字换行、图表不超屏 */
@media (max-width: 720px) {
  #expand_cpu {
    white-space: normal;
    word-break: break-word;
    max-width: calc(100vw - 2rem);
  }

  .expand-inner {
    max-width: calc(100vw - 2rem);
  }

  .ping-chart-wrap {
    max-width: 100%;
    overflow: hidden;
  }

  :deep(.ping-chart) {
    max-width: 100%;
  }
}
</style>
