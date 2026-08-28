<template>
  <table class="ui basic unstackable table" id="table">
    <thead>
    <tr>
      <th id="status4">运行状态</th>
      <th id="name">节点名</th>
      <th id="os">系统</th>
      <th id="location">服务器位置</th>
      <th id="uptime">在线时间</th>
      <th id="load">负载</th>
      <th id="network">网络(B/s) ↓|↑</th>
      <th id="traffic">流量(B) ↓|↑</th>
      <th id="cpu">CPU</th>
      <th id="ram">内存</th>
      <th id="hdd">硬盘</th>
    </tr>
    </thead>
    <tbody id="servers">
    <tr v-if="loading" class="hotaru-skeleton">
      <td class="hotaru-skeleton-td hotaru-skeleton-td--merged" colspan="11">加载中…</td>
    </tr>
    <table-item v-for="(server, index) of servers" :key="index" :server="server" :history="history"/>
    </tbody>
  </table>
</template>
<script lang="ts">
import { defineComponent, PropType } from 'vue';
import TableItem from '@/components/TableItem.vue';
import { StatusItem } from '@/types';

export default defineComponent({
  name: 'ServersTable',
  props: {
    servers: {
      type: Array as PropType<Array<StatusItem>>,
      default: () => ([])
    },
    history: {
      type: Object as PropType<Record<string, {t: number; iv: number; v: number[]}>>,
      default: () => ({})
    },
    loading: {
      type: Boolean,
      default: false
    }
  },
  components: {
    TableItem
  }
});
</script>
<style>
#table {
  font-size: 1rem;
  border: none;
  text-align: center;
  vertical-align: middle;
}

#table thead tr th {
  color: var(--hotaru-faint);
  white-space: nowrap;
  border-bottom: 1px solid rgba(34, 36, 38, .1);
}

tr.hotaru-skeleton td.hotaru-skeleton-td {
  color: var(--hotaru-text);
  font-weight: 400;
  background: transparent;
  border: none;
  white-space: normal;
  word-break: break-word;
  padding: 1.6em .78571429em;
  text-align: center;
}
</style>
