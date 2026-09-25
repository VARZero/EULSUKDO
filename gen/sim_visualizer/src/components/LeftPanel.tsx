import React from 'react';
import { type VcdData } from '../utils/vcdParser';

interface LeftPanelProps {
  selectedModule: string;
  onSelectModule: (module: string) => void;
  vcdData: VcdData | null;
  currentCycleIndex: number;
}

export const LeftPanel: React.FC<LeftPanelProps> = ({
  selectedModule,
  onSelectModule,
  vcdData,
  currentCycleIndex,
}) => {
  // Helper to extract a signal's current value by fuzzy name matching
  const getSignalValue = (pattern: string): string => {
    if (!vcdData || vcdData.cycles.length === 0) return 'x';
    const cycle = vcdData.cycles[Math.min(currentCycleIndex, vcdData.cycles.length - 1)];

    // Find a variable that contains the pattern
    const variable = vcdData.vars.find(v =>
      v.name.toLowerCase() === pattern.toLowerCase()
    );

    if (!variable) return 'x';
    const val = cycle.values[variable.id];

    // Format binary values to hex for display if they are multi-bit
    if (val && val.length > 1 && !val.includes('x') && !val.includes('z')) {
      try {
        const hex = parseInt(val, 2).toString(16).toUpperCase();
        return '0x' + hex;
      } catch {
        return val;
      }
    }
    return val || 'x';
  };

  // Check if a flow transition is active based on validity signals
  const isTransitionActive = (validPattern: string): boolean => {
    const val = getSignalValue(validPattern);
    return val !== '0' && val !== '0x0' && val !== 'x' && val !== 'z';
  };

  const getModuleStatus = (moduleName: string): string => {
    if (moduleName === 'nel') {
      return getSignalValue('i_im_recv_inst_valid') === '0' ? 'IDLE' : 'RECEIVE';
    }
    if (moduleName === 'ist') {
      return getSignalValue('ist_rs_ready_inst_valid') === '0' ? 'WAIT' : 'READY';
    }
    return 'READY';
  };

  return (
    <div className="left-container">
      <div className="panel-header">
        <div className="panel-title">
          <span className="panel-title-accent">01 //</span> 을숙도 Gen 모듈 다이어그램
        </div>
        <div style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>
          모듈 클릭시 우측에서 상세 정보 확인 가능
        </div>
      </div>

      <div className="diagram-wrapper">
        <svg className="diagram-svg" viewBox="0 0 520 540">
          <defs>
            <marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
              <path d="M 0 1 L 10 5 L 0 9 z" fill="#ff5500" />
            </marker>
            <marker id="arrow-gray" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
              <path d="M 0 1 L 10 5 L 0 9 z" fill="#262626" />
            </marker>
          </defs>

          {/* BACKGROUND GRID */}
          <pattern id="grid" width="20" height="20" patternUnits="userSpaceOnUse">
            <path d="M 20 0 L 0 0 0 20" fill="none" stroke="rgba(255, 85, 0, 0.02)" strokeWidth="1" />
          </pattern>
          <rect width="100%" height="100%" fill="url(#grid)" />

          {/* CONNECTIONS (LINES) */}

          {/* FCL -> NEL */}
          <path
            className={`connection-line ${isTransitionActive('i_im_recv_inst_valid') ? 'active' : ''}`}
            d="M 125 100 L 250 100"
            markerEnd={isTransitionActive('i_im_recv_inst_valid') ? "url(#arrow)" : "url(#arrow-gray)"}
          />
          <text x="145" y="92" className="signal-badge">
            PC: {getSignalValue('o_im_req_pc')}
          </text>

          {/* NEL -> IST */}
          <path
            className={`connection-line ${isTransitionActive('nel_ist_new_inst_valid') ? 'active' : ''}`}
            d="M 310 135 L 310 185"
            markerEnd={isTransitionActive('nel_ist_new_inst_valid') ? "url(#arrow)" : "url(#arrow-gray)"}
          />
          <text x="316" y="160" className="signal-badge">
            Insert: {getSignalValue('nel_ist_new_inst_valid')}
          </text>

          {/* NEL -> PRM */}
          <path
            className={`connection-line ${isTransitionActive('prm_nel_phyreg_valid') ? 'active' : ''}`}
            d="M 250 120 L 125 195"
            markerEnd={isTransitionActive('prm_nel_phyreg_valid') ? "url(#arrow)" : "url(#arrow-gray)"}
          />
          <text x="140" y="150" className="signal-badge">
            Alloc: {getSignalValue('prm_nel_phyreg_valid')}
          </text>

          {/* PRM -> IST */}
          <path
            className={`connection-line ${isTransitionActive('prm_ist_ready_phyreg_valid') ? 'active' : ''}`}
            d="M 125 220 L 250 220"
            markerEnd={isTransitionActive('prm_ist_ready_phyreg_valid') ? "url(#arrow)" : "url(#arrow-gray)"}
          />
          <text x="145" y="215" className="signal-badge">
            Ready Upd: {getSignalValue('prm_ist_ready_phyreg_valid')}
          </text>

          {/* IST -> RS */}
          <path
            className={`connection-line ${isTransitionActive('ist_rs_ready_inst_valid') ? 'active' : ''}`}
            d="M 310 255 L 310 305"
            markerEnd={isTransitionActive('ist_rs_ready_inst_valid') ? "url(#arrow)" : "url(#arrow-gray)"}
          />
          <text x="316" y="280" className="signal-badge">
            Push RS: {getSignalValue('ist_rs_ready_inst_valid')}
          </text>

          {/* RS -> EX */}
          <path
            className={`connection-line ${isTransitionActive('o_rs_entry_valid') ? 'active' : ''}`}
            d="M 310 375 L 310 425"
            markerEnd={isTransitionActive('o_rs_entry_valid') ? "url(#arrow)" : "url(#arrow-gray)"}
          />
          <text x="316" y="400" className="signal-badge">
            Issue: {getSignalValue('o_rs_entry_valid')}
          </text>

          {/* EX -> WBC */}
          <path
            className={`connection-line ${isTransitionActive('i_wbc_result_valid') ? 'active' : ''}`}
            d="M 250 460 L 95 460 L 95 385"
            markerEnd={isTransitionActive('i_wbc_result_valid') ? "url(#arrow)" : "url(#arrow-gray)"}
          />

          {/* WBC -> PRM */}
          <path
            className={`connection-line ${isTransitionActive('wbc_broadcast_done_phyreg_valid') ? 'active' : ''}`}
            d="M 70 315 L 70 265"
            markerEnd={isTransitionActive('wbc_broadcast_done_phyreg_valid') ? "url(#arrow)" : "url(#arrow-gray)"}
          />
          <text x="10" y="295" className="signal-badge">
            WB Done: {getSignalValue('wbc_broadcast_done_phyreg_valid')}
          </text>

          {/* WBC -> FCL */}
          <path
            className={`connection-line ${isTransitionActive('wbc_fcl_done_pc_valid') ? 'active' : ''}`}
            d="M 95 315 L 95 135"
            markerEnd={isTransitionActive('wbc_fcl_done_pc_valid') ? "url(#arrow)" : "url(#arrow-gray)"}
          />
          <text x="102" y="160" className="signal-badge">
            Done PC
          </text>

          {/* FCL -> PRM */}
          <path
            className={`connection-line ${isTransitionActive('fcl_prm_unallocate_phyreg_valid') ? 'active' : ''}`}
            d="M 70 135 L 70 185"
            markerEnd={isTransitionActive('fcl_prm_unallocate_phyreg_valid') ? "url(#arrow)" : "url(#arrow-gray)"}
          />
          <text x="10" y="160" className="signal-badge">
            Unalloc
          </text>


          {/* MODULE NODES */}

          {/* 1. Flow Control Logic (FCL) */}
          <g className={`module-node ${selectedModule === 'fcl' ? 'active' : ''}`} onClick={() => onSelectModule('fcl')}>
            <rect x="20" y="60" width="105" height="75" rx="5" />
            <text x="72.5" y="95" textAnchor="middle" fontWeight="bold">Flow Control</text>
            <text x="72.5" y="112" textAnchor="middle" fontSize="10" fill="var(--accent-orange)">(FCL)</text>
          </g>

          {/* 2. New Entry Logic (NEL) */}
          <g className={`module-node ${selectedModule === 'nel' ? 'active' : ''}`} onClick={() => onSelectModule('nel')}>
            <rect x="250" y="60" width="120" height="75" rx="5" />
            <text x="310" y="90" textAnchor="middle" fontWeight="bold">New Entry Logic</text>
            <text x="310" y="105" textAnchor="middle" fontSize="10" fill="var(--accent-orange)">(NEL)</text>
            <text x="310" y="120" textAnchor="middle" fontSize="9" fill="var(--text-muted)">{getModuleStatus('nel')}</text>
          </g>

          {/* 3. Physical Register Mapper (PRM) */}
          <g className={`module-node ${selectedModule === 'prm' ? 'active' : ''}`} onClick={() => onSelectModule('prm')}>
            <rect x="20" y="185" width="105" height="80" rx="5" />
            <text x="72.5" y="215" textAnchor="middle" fontWeight="bold">Phys Reg Map</text>
            <text x="72.5" y="232" textAnchor="middle" fontSize="10" fill="var(--accent-orange)">(PRM)</text>
            <text x="72.5" y="248" textAnchor="middle" fontSize="9" fill="var(--text-muted)">Ready-Status RF</text>
          </g>

          {/* 4. Instruction State Table (IST) */}
          <g className={`module-node ${selectedModule === 'ist' ? 'active' : ''}`} onClick={() => onSelectModule('ist')}>
            <rect x="250" y="185" width="120" height="70" rx="5" />
            <text x="310" y="212" textAnchor="middle" fontWeight="bold">Inst State Table</text>
            <text x="310" y="227" textAnchor="middle" fontSize="10" fill="var(--accent-orange)">(IST)</text>
            <text x="310" y="242" textAnchor="middle" fontSize="9" fill="var(--text-muted)">{getModuleStatus('ist')}</text>
          </g>

          {/* 5. Ready Station (RS) */}
          <g className={`module-node ${selectedModule === 'rs' ? 'active' : ''}`} onClick={() => onSelectModule('rs')}>
            <rect x="250" y="305" width="120" height="70" rx="5" />
            <text x="310" y="332" textAnchor="middle" fontWeight="bold">Ready Station</text>
            <text x="310" y="347" textAnchor="middle" fontSize="10" fill="var(--accent-orange)">(RS)</text>
            <text x="310" y="362" textAnchor="middle" fontSize="9" fill="var(--text-muted)">Issue Queues</text>
          </g>

          {/* 6. Execution Unit (EX) */}
          <g className={`module-node ${selectedModule === 'ex' ? 'active' : ''}`} onClick={() => onSelectModule('ex')}>
            <rect x="250" y="425" width="120" height="70" rx="5" />
            <text x="310" y="452" textAnchor="middle" fontWeight="bold">Execution Cores</text>
            <text x="310" y="467" textAnchor="middle" fontSize="10" fill="var(--accent-orange)">(EX Paths)</text>
            <text x="310" y="482" textAnchor="middle" fontSize="9" fill="var(--text-muted)">ALU / BR / MEM</text>
          </g>

          {/* 7. Write Back Concatenation (WBC) */}
          <g className={`module-node ${selectedModule === 'wbc' ? 'active' : ''}`} onClick={() => onSelectModule('wbc')}>
            <rect x="20" y="315" width="105" height="70" rx="5" />
            <text x="72.5" y="342" textAnchor="middle" fontWeight="bold">Writeback</text>
            <text x="72.5" y="357" textAnchor="middle" fontSize="10" fill="var(--accent-orange)">(WBC)</text>
            <text x="72.5" y="372" textAnchor="middle" fontSize="9" fill="var(--text-muted)">Broadcasting</text>
          </g>
        </svg>
      </div>
    </div>
  );
};
