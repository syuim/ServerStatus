<template>
  <tr class="tableRow" @click="collapsed = !collapsed">
    <td>
      <div class="ui progress" :class="{'success': getStatus, 'error': !getStatus}">
        <div class="bar" style="width: 100%"><span> {{ getStatus ? '运行中' : '维护中' }} </span>
        </div>
      </div>
    </td>
    <td>{{ server.name }}</td>
    <td>{{ osName }}</td>
    <td>{{ server.location }}</td>
    <td>{{ server.uptime || '–' }}</td>
    <td>{{ getStatus ? server.load : '-' }}</td>
    <td>{{
        getStatus ? `${tableRowByteConvert(server.network_rx)} | ${tableRowByteConvert(server.network_tx)}` : '–'
      }}
    </td>
    <td>{{
        getStatus ? `${tableRowByteConvert(server.network_in)} | ${tableRowByteConvert(server.network_out)}` : '–'
      }}
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
        <div class="tag-line" v-if="getStatus && tags.length">
          <span v-for="(tag, i) of tags" :key="i" class="tag" :class="'tag--' + (tag.color || 'grey')">{{
              tag.text
            }}</span>
        </div>
        <div class="ping-panel" v-if="getStatus && pingSeries.length" @click.stop>
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
            <svg class="ping-chart" :viewBox="`0 0 ${CHART_W} ${CHART_H}`" preserveAspectRatio="none">
              <g v-for="gy in gridYs" :key="gy">
                <line :x1="0" :y1="gy" :x2="CHART_W" :y2="gy" class="grid-line"/>
              </g>
              <rect v-for="b in activeBars" :key="b.i" :x="b.x" :y="b.y" :width="b.w" :height="b.h" class="ping-bar"/>
            </svg>
            <div class="ping-axis" v-if="axisStart && axisEnd">
              <span>{{ axisStart }}</span>
              <span>{{ axisEnd }}</span>
            </div>
          </div>
        </div>
      </div>
    </td>
  </tr>
</template>

<script lang="ts">
import { defineComponent, ref, computed, PropType } from 'vue';
import useStatus from './useStatus';
import { StatusItem } from '@/types';

interface CustomTag {
  text: string;
  color?: string;
}

interface CustomData {
  os?: string;
  cpu_model?: string;
  cores?: number;
  tags?: CustomTag[];
  ping?: Record<string, number[]>;
}

const CHART_W = 560;
const CHART_H = 200;

export default defineComponent({
  name: 'TableItem',
  props: {
    server: {
      type: Object as PropType<StatusItem>,
      default: () => ({})
    }
  },
  setup(props) {
    const collapsed = ref(true);
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
      return d.cpu_model.replace(/\s*\d+\s*[-–]?\s*Core\s*Processor$/i, '').trim();
    });
    const osName = computed(() => {
      const d = customData.value;
      return d && d.os ? d.os : '–';
    });
    const tags = computed<CustomTag[]>(() => {
      const d = customData.value;
      return d && Array.isArray(d.tags) ? d.tags : [];
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
        .map(name => ({name, values: raw[name] as number[], startTs: t, iv}));
    });
    const activePing = ref('');
    const currentSeries = computed(() => {
      const list = pingSeries.value;
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
    const fmtTime = (ts: number) => {
      const d = new Date(ts * 1000);
      const p = (n: number) => String(n).padStart(2, '0');
      return `${p(d.getHours())}:${p(d.getMinutes())}`;
    };
    const axisStart = computed(() => {
      const s = currentSeries.value;
      if (!s || !s.startTs || s.values.length < 2) return '';
      return fmtTime(s.startTs - (s.values.length - 1) * s.iv);
    });
    const axisEnd = computed(() => {
      const s = currentSeries.value;
      if (!s || !s.startTs || s.values.length < 2) return '';
      return fmtTime(s.startTs);
    });
    const yScale = computed(() => {
      const vals = validValues.value;
      const max = vals.length ? Math.max(...vals) : 0;
      return Math.max(50, Math.ceil(max / 100) * 100);
    });
    const gridYs = computed(() => {
      const step = yScale.value / 4;
      return [1, 2, 3].map(i => Math.round(CHART_H - (i * step) / yScale.value * CHART_H));
    });
    const activeBars = computed(() => {
      const s = currentSeries.value;
      if (!s) return [];
      const n = s.values.length;
      const slot = CHART_W / n;
      const barW = Math.max(2, slot * 0.55);
      const bars: Array<{ i: number; x: number; y: number; w: number; h: number }> = [];
      s.values.forEach((v, i) => {
        if (v < 0) return;
        const h = Math.min(v / yScale.value, 1) * (CHART_H - 20);
        bars.push({
          i,
          x: i * slot + (slot - barW) / 2,
          y: CHART_H - 16 - h,
          w: barW,
          h
        });
      });
      return bars;
    });
    return {
      collapsed,
      cpuModel,
      osName,
      tags,
      pingSeries,
      activePing,
      activeAvgText,
      activeLossText,
      axisStart,
      axisEnd,
      activeBars,
      gridYs,
      CHART_W,
      CHART_H,
      ...utils
    };
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
  margin-top: .5em;
}

.ping-head {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-bottom: 10px;
}

.ping-tabs {
  display: flex;
  gap: 5px;
}

.ping-tab {
  border: none;
  border-radius: 6px;
  background: #e8e8e8;
  color: #616366;
  font-weight: 700;
  font-size: .8rem;
  line-height: 1;
  padding: 4px 10px;
  cursor: pointer;
}

.ping-tab.active {
  background: #21BA45;
  color: #fff;
}

.ping-stats {
  display: flex;
  gap: 6px;
  margin-left: auto;
}

.ping-stat {
  background: rgba(0, 0, 0, .05);
  border-radius: 4px;
  color: #616366;
  font-size: .78rem;
  font-weight: 700;
  line-height: 1;
  padding: 5.5px 9px;
}

.ping-chart-wrap {
  position: relative;
}

.ping-chart {
  display: block;
  width: 100%;
  height: 200px;
}

.ping-axis {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 2px;
  display: flex;
  justify-content: space-between;
  font-size: 11px;
  color: #9da2a6;
  font-weight: 500;
  pointer-events: none;
}

.grid-line {
  stroke: rgba(0, 0, 0, .06);
  stroke-width: 1;
}

.ping-bar {
  fill: #21BA45;
}

div.progress {
  display: inline-block;
  overflow: hidden;
  height: 22px;
  width: 50px;
  border-radius: 6px;
  background: rgba(0, 0, 0, .1);
  margin-bottom: 0 !important;
}

div.progress div.bar {
  height: 22px;
  border-radius: 6px;
  font-size: .85rem;
  line-height: 22px;
  color: white;
  transition: width .1s ease, background-color .1s ease;
}

tr td {
  color: #616366;
  font-weight: bold;
  border: none !important;
  white-space: nowrap;
}
</style>
