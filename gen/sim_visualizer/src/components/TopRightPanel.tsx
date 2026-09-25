import React from 'react';
import { type VcdData } from '../utils/vcdParser';

interface TopRightPanelProps {
  selectedModule: string;
  vcdData: VcdData | null;
  currentCycleIndex: number;
  config: { scheduler?: { decodeWidth?: number; phyRegs?: number; robEntries?: number; coresList?: { count: number }[] } };
}

const moduleSignals: Record<string, string[]> = {
  nel: ['i_im_recv_inst_valid', 'o_im_recv_inst_get', 'i_im_recv_pc', 'i_nel_decode_rd', 'i_nel_decode_rs', 'i_nel_decode_expath', 'nel_ist_new_inst_valid', 'nel_ist_new_inst_data', 'nel_fcl_retired_phyreg_valid'],
  prm: ['prm_nel_phyreg_valid', 'prm_nel_phyreg_data', 'prm_ist_ready_phyreg_valid', 'prm_ist_ready_phyreg_data', 'ist_prm_wait_phyreg_valid', 'wbc_broadcast_done_phyreg_valid', 'fcl_prm_unallocate_phyreg_valid'],
  ist: ['nel_ist_new_inst_valid', 'nel_ist_new_inst_get', 'ist_prm_wait_phyreg_valid', 'prm_ist_ready_phyreg_valid', 'ist_rs_ready_inst_valid', 'ist_rs_ready_inst_get', 'ist_rs_ready_inst_data'],
  rs: ['ist_rs_ready_inst_valid', 'ist_rs_ready_inst_get', 'rs_ex_wait_inst_valid', 'rs_ex_wait_inst_get', 'o_rs_entry_valid', 'i_rs_entry_get', 'o_rs_entry_data'],
  ex: ['o_rs_entry_valid', 'i_rs_entry_get', 'o_rs_entry_data', 'i_wbc_result_valid', 'i_wbc_result_data', 'i_wbc_result_branch_valid', 'i_wbc_result_branch_data'],
  wbc: ['i_wbc_result_valid', 'i_wbc_result_data', 'i_wbc_result_branch_valid', 'wbc_fcl_done_pc_valid', 'wbc_fcl_done_pc_data', 'wbc_broadcast_done_phyreg_valid', 'wbc_fcl_branch_valid'],
  fcl: ['o_im_req_pc_valid', 'i_im_req_pc_get', 'o_im_req_pc', 'i_im_recv_inst_valid', 'o_im_recv_inst_get', 'nel_fcl_jumpbranch_valid', 'wbc_fcl_done_pc_valid', 'fcl_prm_unallocate_phyreg_valid'],
};

const titles: Record<string, string> = {
  nel: 'NEW ENTRY LOGIC', prm: 'PHYSICAL REGISTER MAPPER', ist: 'INSTRUCTION STATE TABLE',
  rs: 'READY STATION', ex: 'EXECUTION INTERFACE', wbc: 'WRITE BACK CONCATENATION', fcl: 'FLOW CONTROL LOGIC',
};

export const TopRightPanel: React.FC<TopRightPanelProps> = ({ selectedModule, vcdData, currentCycleIndex, config }) => {
  const cycle = vcdData?.cycles[currentCycleIndex];
  const signals = moduleSignals[selectedModule] || [];
  const findVariable = (name: string) => vcdData?.vars.find(variable =>
    variable.name === name && (variable.fullName.includes('.dut.') || variable.fullName.includes('.U_SCHEDULER_CORE.')))
    || vcdData?.vars.find(variable => variable.name === name);
  const raw = (name: string) => {
    const variable = findVariable(name);
    return variable && cycle ? cycle.values[variable.id] : undefined;
  };
  const format = (value: string | undefined, width: number) => {
    if (value === undefined) return 'VCD에 없음';
    if (/[xz]/i.test(value)) return value;
    return width === 1 ? value : `0x${BigInt(`0b${value}`).toString(16).toUpperCase()}`;
  };
  const laneNames = selectedModule === 'fcl' ? ['o_im_req_pc_valid', 'i_im_req_pc_get']
    : selectedModule === 'ex' || selectedModule === 'rs' ? ['o_rs_entry_valid', 'i_rs_entry_get']
    : selectedModule === 'nel' ? ['i_im_recv_inst_valid', 'o_im_recv_inst_get'] : [];
  const laneCount = laneNames[0] ? findVariable(laneNames[0])?.size ?? 0 : 0;
  const pathCount = config.scheduler?.coresList?.reduce((sum, core) => sum + core.count, 0) ?? 0;

  return (
    <div className="top-right-container">
      <div className="panel-header">
        <div className="panel-title"><span className="panel-title-accent">02 //</span> {titles[selectedModule] || selectedModule}</div>
        <span className="signal-meta">{cycle ? `CYCLE ${cycle.cycle} · T=${cycle.timestamp}${vcdData?.timescale}` : 'VCD를 불러오세요'}</span>
      </div>
      <div className="actual-signal-content">
        <div className="signal-summary">
          <span>DECODE {config.scheduler?.decodeWidth ?? '—'}</span>
          <span>PRF {config.scheduler?.phyRegs ?? '—'}</span>
          <span>IST {config.scheduler?.robEntries ?? '—'}</span>
          <span>EX {pathCount || '—'}</span>
        </div>
        {laneCount > 0 && cycle && <div className="lane-table">
          <h3>Lane handshake (valid / get)</h3>
          {Array.from({ length: laneCount }, (_, index) => {
            const valid = raw(laneNames[0]);
            const get = raw(laneNames[1]);
            const validBit = valid?.[valid.length - 1 - index] || 'x';
            const getBit = get?.[get.length - 1 - index] || 'x';
            return <div className="lane-row" key={index}>
              <span>LANE {index}</span><span>V {validBit}</span><span>G {getBit}</span>
              <strong>{validBit === '1' && getBit === '1' ? 'ACCEPT' : validBit === '1' ? 'WAIT' : 'IDLE'}</strong>
            </div>;
          })}
        </div>}
        <h3>Gen RTL signals</h3>
        <table className="signal-table"><thead><tr><th>Signal</th><th>Width</th><th>Current value</th></tr></thead>
          <tbody>{signals.map(name => {
            const variable = findVariable(name);
            return <tr key={name}><td>{name}</td><td>{variable?.size ?? '—'}</td><td title={variable?.fullName}>
              {format(raw(name), variable?.size ?? 0)}</td></tr>;
          })}</tbody>
        </table>
        <p className="signal-note">상태는 업로드한 VCD의 실제 신호값입니다. 기록되지 않은 내부 신호는 “VCD에 없음”으로 표시합니다.</p>
      </div>
    </div>
  );
};
