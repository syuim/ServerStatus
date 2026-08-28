<template>
  <div class="ping-chart" :class="{'is-ready': ready}">
    <canvas ref="el"></canvas>
    <div class="ping-chart__loading" :hidden="ready"><span></span><span></span><span></span></div>
  </div>
</template>
<script lang="ts">
import { defineComponent, PropType, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import Chart from 'chart.js/auto';
import 'chartjs-adapter-date-fns';

// 与 p4.pw 一致：Chart.js 4.4.0 折线图，Y 轴 0-600ms，超时画到顶部尖峰
const Y_MAX = 600;

// hover 时在鼠标位置画一条竖线
const verticalGuide = {
  id: 'verticalGuide',
  afterDatasetsDraw(chart: Chart) {
    const active = chart.tooltip?.getActiveElements?.() || [];
    if (!active.length) return;
    const x = active[0].element.x;
    const { top, bottom } = chart.chartArea;
    const ctx = chart.ctx;
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(x, top);
    ctx.lineTo(x, bottom);
    ctx.lineWidth = 1.5;
    ctx.strokeStyle = 'rgba(0, 0, 0, .25)';
    ctx.stroke();
    ctx.restore();
  }
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
    const el = ref<HTMLCanvasElement>();
    const ready = ref(false);
    let chart: Chart | null = null;

    const buildData = () => {
      const n = props.values.length;
      return props.values.map((v, i) => ({
        x: (props.startTs - (n - 1 - i) * props.iv) * 1000,
        y: v < 0 ? null : Math.min(v, Y_MAX)
      })) as any;
    };

    const buildConfig = (): any => ({
      type: 'line',
      data: {
        datasets: [{
          data: buildData(),
          borderColor: 'rgba(33, 186, 69, .85)',
          borderWidth: 1.5,
          pointRadius: 0,
          spanGaps: false,
          fill: false,
          tension: 0
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        interaction: { mode: 'index', intersect: false },
        plugins: {
          legend: { display: false },
          tooltip: {
            backgroundColor: 'rgba(255,255,255,.95)',
            borderColor: 'rgba(0,0,0,.08)',
            borderWidth: 1,
            titleColor: '#616366',
            bodyColor: '#616366',
            callbacks: {
              title: (items: Array<{ parsed: { x: number } }>) => {
                const ts = items[0]?.parsed.x;
                if (!ts) return '';
                const d = new Date(ts);
                const p = (v: number) => String(v).padStart(2, '0');
                return `${p(d.getHours())}:${p(d.getMinutes())}`;
              },
              label: (item: { parsed: { y: number | null } }) => {
                const y = item.parsed.y;
                return y === null ? '超时' : `${y}ms`;
              }
            }
          }
        },
        scales: {
          x: {
            type: 'time',
            time: { unit: 'hour', displayFormats: { hour: 'HH:mm' } },
            grid: { display: false },
            ticks: { color: '#9da2a6', font: { size: 11 }, maxTicksLimit: 6 }
          },
          y: {
            min: 0,
            max: Y_MAX,
            grid: { color: 'rgba(0,0,0,.06)' },
            ticks: { display: false }
          }
        }
      }
    });

    onMounted(() => {
      if (!el.value) return;
      chart = new Chart(el.value, { ...buildConfig(), plugins: [verticalGuide] });
      window.setTimeout(() => {
        ready.value = true;
      }, 60);
    });

    watch(
      () => [props.values, props.startTs, props.iv],
      () => {
        if (!chart) return;
        chart.data.datasets[0].data = buildData();
        chart.update('none');
      }
    );

    onBeforeUnmount(() => {
      if (chart) {
        chart.destroy();
        chart = null;
      }
    });

    return { el, ready };
  }
});
</script>
<style scoped>
.ping-chart {
  position: relative;
  width: 100%;
  height: 200px;
}

.ping-chart canvas {
  width: 100% !important;
  height: 100% !important;
  opacity: 0;
  transition: opacity .28s cubic-bezier(.2, .8, .2, 1);
}

.ping-chart.is-ready canvas {
  opacity: 1;
}

.ping-chart__loading {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  pointer-events: none;
}

.ping-chart__loading[hidden] {
  display: none !important;
}

.ping-chart__loading span {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--hotaru-faint);
  animation: ping-chart-dot 1.2s ease-in-out infinite;
}

.ping-chart__loading span:nth-child(2) {
  animation-delay: .15s;
}

.ping-chart__loading span:nth-child(3) {
  animation-delay: .3s;
}

@keyframes ping-chart-dot {
  0%, to {
    opacity: .25;
    transform: translateY(0);
  }
  50% {
    opacity: 1;
    transform: translateY(-3px);
  }
}
</style>
