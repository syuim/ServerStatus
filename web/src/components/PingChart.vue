<template>
  <div ref="el" class="ping-chart"></div>
</template>
<script lang="ts">
import { defineComponent, PropType, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import * as echarts from 'echarts/core';
import { BarChart } from 'echarts/charts';
import { GridComponent, TooltipComponent } from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';

echarts.use([BarChart, GridComponent, TooltipComponent, CanvasRenderer]);

const fmtTime = (ts: number) => {
  const d = new Date(ts * 1000);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${p(d.getHours())}:${p(d.getMinutes())}`;
};

export default defineComponent({
  name: 'PingChart',
  props: {
    values: {
      type: Array as PropType<number[]>,
      default: () => ([])
    },
    startTs: {
      type: Number,
      default: 0
    },
    iv: {
      type: Number,
      default: 60
    }
  },
  setup(props) {
    const el = ref<HTMLDivElement>();
    let chart: ReturnType<typeof echarts.init> | null = null;

    const buildOption = () => {
      const n = props.values.length;
      const labels = props.values.map((_, i) => fmtTime(props.startTs - (n - 1 - i) * props.iv));
      const data = props.values.map(v => v < 0 ? null : v);
      return {
        grid: { left: 4, right: 4, top: 8, bottom: 2, containLabel: true },
        xAxis: {
          type: 'category' as const,
          data: labels,
          axisLine: { show: false },
          axisTick: { show: false },
          axisLabel: {
            color: '#9da2a6',
            fontSize: 11,
            interval: n > 8 ? Math.floor(n / 4) : 0
          }
        },
        yAxis: {
          type: 'value' as const,
          max: (value: { max: number }) => Math.max(50, Math.ceil(value.max / 100) * 100),
          splitLine: { lineStyle: { color: 'rgba(0,0,0,.06)' } },
          axisLabel: { show: false },
          axisLine: { show: false },
          axisTick: { show: false }
        },
        tooltip: {
          trigger: 'axis' as const,
          backgroundColor: 'rgba(255,255,255,.95)',
          borderColor: 'rgba(0,0,0,.08)',
          textStyle: { color: '#616366', fontSize: 12 },
          formatter: (params: Array<{ axisValueLabel: string; value: number | null }>) => {
            const p = params[0];
            return `${p.axisValueLabel} ${p.value === null ? '超时' : p.value + 'ms'}`;
          }
        },
        series: [{
          type: 'bar' as const,
          data,
          barWidth: '55%',
          itemStyle: { color: '#21BA45', borderRadius: [2, 2, 0, 0] }
        }]
      };
    };

    onMounted(() => {
      if (!el.value) return;
      chart = echarts.init(el.value);
      chart.setOption(buildOption());
    });

    watch(
      () => [props.values, props.startTs, props.iv],
      () => {
        if (chart) chart.setOption(buildOption(), { notMerge: true });
      }
    );

    onBeforeUnmount(() => {
      if (chart) {
        chart.dispose();
        chart = null;
      }
    });

    return { el };
  }
});
</script>
<style scoped>
.ping-chart {
  width: 100%;
  height: 200px;
}
</style>
