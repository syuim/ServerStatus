<template>
  <the-error v-show="error"/>
  <div class="container">
    <servers-table :servers="servers || []" :history="history" :loading="loading"/>
    <update-time :updated="updated"/>
  </div>
</template>

<script lang="ts">
import { defineComponent, ref, onMounted, onBeforeUnmount, provide } from 'vue';
import axios from 'axios';

import TheError from '@/components/TheError.vue';
import ServersTable from '@/components/ServersTable.vue';
import UpdateTime from '@/components/UpdateTime.vue';
import { BoxItem, StatusItem } from '@/types';

interface PingHistoryEntry {
  t: number;
  iv: number;
  v: number[];
}

export default defineComponent({
  name: 'App',
  components: {
    TheError,
    ServersTable,
    UpdateTime
  },
  setup() {
    const servers = ref<Array<StatusItem | BoxItem>>();
    const history = ref<Record<string, PingHistoryEntry>>({});
    const updated = ref<number>();
    const loading = ref(true);
    const error = ref(false);
    const { interval } = window.__PRE_CONFIG__;
    let timer: number;
    let historyTimer: number;
    const hideInitialLoader = () => {
      const el = document.getElementById('initial-loader');
      if (el) el.classList.add('is-done');
      loading.value = false;
    };
    const runFetch = () => axios.get('json/stats.json')
      .then(res => {
        servers.value = res.data.servers;
        updated.value = Number(res.data.updated);
        hideInitialLoader();
      })
      .catch(err => {
        error.value = true;
        hideInitialLoader();
        console.log(err);
      });
    const runHistoryFetch = () => axios.get('json/history.json')
      .then(res => {
        history.value = res.data.ping || {};
      })
      .catch(() => { /* 旧服务端无 history.json 时忽略 */ });
    // 延迟历史懒加载：页面打开不请求，首次展开行时才拉取并启动轮询
    const historyStarted = ref(false);
    const ensureHistory = () => {
      if (historyStarted.value) return;
      historyStarted.value = true;
      runHistoryFetch();
      historyTimer = setInterval(runHistoryFetch, 30000);
    };
    provide('ensureHistory', ensureHistory);
    onMounted(() => {
      runFetch();
      timer = setInterval(runFetch, interval * 1000);
    });
    onBeforeUnmount(() => {
      clearInterval(timer);
      clearInterval(historyTimer);
    });
    return {
      servers,
      history,
      updated,
      loading,
      error
    };
  }
});
</script>

<style>
:root {
  --hotaru-text: #616366;
  --hotaru-muted: #919699;
  --hotaru-faint: #9da2a6;
  --hotaru-line: rgba(0, 0, 0, .06);
  --hotaru-card-bg: rgba(255, 255, 255, .8);
  --hotaru-row-bg: rgba(249, 249, 249, .8);
  --hotaru-shadow: 5px 5px 25px 0 rgba(46, 61, 73, .2);
  --hotaru-shadow-sm: 0 2px 6px rgba(46, 61, 73, .08);
  --hotaru-radius: 8px;
  --hotaru-radius-lg: 12px;
  --hotaru-radius-xl: 18px;
  --hotaru-status-ok: #21BA45;
  --hotaru-status-warn: #F2C037;
  --hotaru-status-bad: #DB2828;
  --hotaru-status-off: #9b9fa3;
}

.hotaru-initial-loader {
  position: fixed;
  inset: 0;
  z-index: 9999;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #fff;
  color: #616366;
  font-size: 1rem;
  letter-spacing: .02em;
  transition: opacity .32s cubic-bezier(.2, .8, .2, 1);
}

.hotaru-initial-loader.is-done {
  opacity: 0;
  pointer-events: none;
}

.hotaru-initial-loader__text {
  font-weight: 400;
  display: inline-block;
}

.hotaru-initial-loader__ellipsis {
  display: inline-block;
  width: 1em;
  text-align: left;
  letter-spacing: .05em;
}

.hotaru-initial-loader__ellipsis > span {
  opacity: 0;
  animation: 1.4s steps(1, end) infinite;
}

.hotaru-initial-loader__ellipsis > span:nth-child(1) {
  animation-name: hotaru-ellipsis-1;
}

.hotaru-initial-loader__ellipsis > span:nth-child(2) {
  animation-name: hotaru-ellipsis-2;
}

.hotaru-initial-loader__ellipsis > span:nth-child(3) {
  animation-name: hotaru-ellipsis-3;
}

@keyframes hotaru-ellipsis-1 {
  0% { opacity: 0; }
  33% { opacity: 1; }
}

@keyframes hotaru-ellipsis-2 {
  0%, 33% { opacity: 0; }
  66% { opacity: 1; }
}

@keyframes hotaru-ellipsis-3 {
  0%, 66% { opacity: 0; }
  100% { opacity: 1; }
}
</style>

<style>
html {
  font-size: 14px;
}

body {
  background: #f0f2f5;
  font-family: "LXGW WenKai Screen R", -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC",
    "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
}

/*Global*/
div.bar {
  min-width: 0 !important;
}

/*Responsive*/
@media only screen and (min-width: 1200px) {
  .container {
    width: 1155px;
    margin: 0 auto;
  }
}

@media only screen and (max-width: 1200px) {
  #app .container {
    width: auto;
    margin: 0 .8rem;
  }

  #table thead tr th, #table tr.tableRow td {
    padding: .7em;
  }
}

@media only screen and (max-width: 1075px) {
  #os, tr td:nth-child(3) {
    display: none;
  }
}

@media only screen and (max-width: 992px) {
  html, body {
    font-size: 13px;
  }
}

@media only screen and (max-width: 910px) {
  #uptime, tr td:nth-child(5) {
    display: none;
  }

  #load, tr td:nth-child(6) {
    display: none;
  }

  #traffic, tr td:nth-child(8) {
    display: none;
  }
}

@media (max-width: 768px) {
  html, body {
    font-size: 12px;
  }
}

/* 移动端只保留: 运行状态 / 节点名 / 网络 / CPU */
@media only screen and (max-width: 720px) {
  #table {
    overflow-x: auto;
    display: block;
    -webkit-overflow-scrolling: touch;
  }

  #location, tr td:nth-child(4) {
    display: none;
  }

  #ram, tr td:nth-child(10) {
    display: none;
  }

  #hdd, tr td:nth-child(11) {
    display: none;
  }

  #name, tr td:nth-child(2) {
    min-width: 20px;
    max-width: 60px;
    text-overflow: ellipsis;
    overflow: hidden;
  }

  /* 状态标记缩小为圆点 */
  #table tr.tableRow td:first-child {
    padding: .3em .2em !important;
  }

  #table tr.tableRow td:first-child div.progress {
    max-width: 14px !important;
    min-width: 14px !important;
    height: 14px;
    border-radius: 50%;
    background: rgba(0,0,0,.1);
  }

  #table tr.tableRow td:first-child div.progress div.bar {
    height: 14px;
    line-height: 14px;
    border-radius: 50%;
    font-size: 0;
    padding: 0;
    color: transparent;
  }

  #table tr.tableRow td:first-child div.progress div.bar span {
    display: none;
  }
}
</style>
