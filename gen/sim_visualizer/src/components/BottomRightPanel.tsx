import React, { useState, useEffect } from 'react';
import { type VcdData } from '../utils/vcdParser';
import { WaveformCanvas } from './WaveformCanvas';

interface BottomRightPanelProps {
  selectedModule: string;
  vcdData: VcdData | null;
  currentCycleIndex: number;
  onSelectCycle: (index: number) => void;
}

export const BottomRightPanel: React.FC<BottomRightPanelProps> = ({
  selectedModule,
  vcdData,
  currentCycleIndex,
  onSelectCycle,
}) => {
  const [selectedSignalIds, setSelectedSignalIds] = useState<string[]>([]);
  const [zoomLevel, setZoomLevel] = useState<number>(1.0);
  const [scrollLeft, setScrollLeft] = useState<number>(0);
  const [isModalOpen, setIsModalOpen] = useState<boolean>(false);
  const [searchQuery, setSearchQuery] = useState<string>('');

  // Auto-populate relevant signals when selected module changes
  useEffect(() => {
    if (!vcdData) return;

    // Default filters based on selected module
    const filters: Record<string, string[]> = {
      nel: ['clk', 'reset_n', 'i_im_recv_inst_valid', 'o_im_recv_inst_get', 'nel_ist_new_inst_valid', 'i_nel_decode_rd'],
      ist: ['clk', 'nel_ist_new_inst_valid', 'ist_rs_ready_inst_valid', 'prm_ist_ready_phyreg_valid'],
      prm: ['clk', 'prm_nel_phyreg_valid', 'ist_prm_wait_phyreg_valid', 'fcl_prm_unallocate_phyreg_valid'],
      rs: ['clk', 'ist_rs_ready_inst_valid', 'o_rs_entry_valid', 'i_rs_entry_get'],
      ex: ['clk', 'o_rs_entry_valid', 'i_rs_entry_get', 'i_wbc_result_valid', 'i_wbc_result_branch_valid'],
      wbc: ['clk', 'i_wbc_result_valid', 'wbc_fcl_done_pc_valid', 'wbc_broadcast_done_phyreg_valid'],
      fcl: ['clk', 'reset_n', 'o_im_req_pc_valid', 'i_im_req_pc_get', 'wbc_fcl_branch_valid'],
    };

    const moduleFilters = filters[selectedModule] || ['clk', 'reset_n'];

    // Find variables matching these filters
    const matchedIds: string[] = [];

    // Always put clk and reset_n first if they exist
    const clkVar = vcdData.vars.find(v => v.name.toLowerCase() === 'clk');
    const rstVar = vcdData.vars.find(v => v.name.toLowerCase() === 'reset_n');
    if (clkVar) matchedIds.push(clkVar.id);
    if (rstVar) matchedIds.push(rstVar.id);

    moduleFilters.forEach(f => {
      if (f === 'clk' || f === 'reset_n') return;
      vcdData.vars.forEach(v => {
        if (v.name.toLowerCase().includes(f.toLowerCase()) && !matchedIds.includes(v.id)) {
          matchedIds.push(v.id);
        }
      });
    });

    // Fallback: If nothing matched, put first 5 signals
    if (matchedIds.length <= 2) {
      vcdData.vars.slice(0, 5).forEach(v => {
        if (!matchedIds.includes(v.id)) {
          matchedIds.push(v.id);
        }
      });
    }

    setSelectedSignalIds(matchedIds);
  }, [selectedModule, vcdData]);

  if (!vcdData) {
    return (
      <div className="bottom-right-container">
        <div className="panel-header">
          <div className="panel-title">
            <span className="panel-title-accent">03 //</span> 시뮬레이션 Waveform (파형 분석)
          </div>
        </div>
        <div style={{ padding: '24px', textAlign: 'center', color: 'var(--text-secondary)' }}>
          시뮬레이션 분석을 시작하려면 VCD 파일을 업로드하거나 예시 데이터를 로드하세요.
        </div>
      </div>
    );
  }

  const handleZoomIn = () => setZoomLevel(prev => Math.min(prev * 1.3, 10));
  const handleZoomOut = () => setZoomLevel(prev => Math.max(prev / 1.3, 0.2));
  const handleResetZoom = () => {
    setZoomLevel(1.0);
    setScrollLeft(0);
  };

  const handleScrollLeft = () => setScrollLeft(prev => Math.max(prev - 100, 0));
  const handleScrollRight = () => setScrollLeft(prev => prev + 100);

  const toggleSignalSelection = (id: string) => {
    setSelectedSignalIds(prev =>
      prev.includes(id) ? prev.filter(sid => sid !== id) : [...prev, id]
    );
  };

  const removeSignal = (id: string) => {
    setSelectedSignalIds(prev => prev.filter(sid => sid !== id));
  };

  const filteredVars = searchQuery
    ? vcdData.vars.filter(v => v.fullName.toLowerCase().includes(searchQuery.toLowerCase()))
    : vcdData.vars;

  return (
    <div className="bottom-right-container">
      <div className="panel-header">
        <div className="panel-title">
          <span className="panel-title-accent">03 //</span> 시뮬레이션 Waveform (파형 분석)
        </div>
        <div className="toolbar-group">
          <span style={{ fontSize: '11px', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>
            타임스케일: {vcdData.timescale} // 줌 배율: {zoomLevel.toFixed(1)}x
          </span>
        </div>
      </div>

      <div className="waveform-toolbar">
        <div className="toolbar-group">
          <button className="btn-sample" style={{ padding: '4px 10px', fontSize: '11px' }} onClick={() => setIsModalOpen(true)}>
            + 신호 추가
          </button>
          <button className="toolbar-btn" onClick={() => setSelectedSignalIds([])}>
            신호 초기화
          </button>
        </div>
        <div className="toolbar-group">
          <button className="toolbar-btn" onClick={handleScrollLeft}>◀ 이동</button>
          <button className="toolbar-btn" onClick={handleScrollRight}>이동 ▶</button>
          <button className="toolbar-btn" onClick={handleZoomOut}>Zoom -</button>
          <button className="toolbar-btn" onClick={handleZoomIn}>Zoom +</button>
          <button className="toolbar-btn" onClick={handleResetZoom}>1:1 비율</button>
        </div>
      </div>

      <div className="waveform-container">
        {/* Left List representing the order on the canvas */}
        <div className="waveform-sidebar">
          <div className="waveform-sidebar-header">신호 목록</div>
          <div className="waveform-sidebar-list">
            {selectedSignalIds.map(sigId => {
              const v = vcdData.varsById[sigId];
              if (!v) return null;
              return (
                <div key={sigId} className="waveform-sidebar-item">
                  <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', width: '130px' }}>
                    {v.name}
                  </span>
                  <button
                    style={{ color: 'var(--text-muted)', fontSize: '10px' }}
                    onClick={(e) => {
                      e.stopPropagation();
                      removeSignal(sigId);
                    }}
                  >
                    ×
                  </button>
                </div>
              );
            })}
          </div>
        </div>

        {/* Waveform drawing Canvas */}
        <WaveformCanvas
          vcdData={vcdData}
          selectedSignals={selectedSignalIds}
          currentCycleIndex={currentCycleIndex}
          onSelectCycle={onSelectCycle}
          zoomLevel={zoomLevel}
          scrollLeft={scrollLeft}
        />
      </div>

      {/* Signal Selection Modal */}
      {isModalOpen && (
        <div className="modal-overlay">
          <div className="modal-content">
            <div className="modal-header">
              <span className="modal-title">Waveform에 시뮬레이션 신호 추가</span>
              <button className="modal-close" onClick={() => setIsModalOpen(false)}>×</button>
            </div>
            <div className="modal-search">
              <input
                type="text"
                placeholder="신호 이름 또는 경로 검색 (예: nel_block, U_FCL.clk)..."
                className="search-input"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
            </div>
            <div className="modal-body">
              {filteredVars.map(v => {
                const isSelected = selectedSignalIds.includes(v.id);
                return (
                  <div key={v.id} className="signal-list-item" onClick={() => toggleSignalSelection(v.id)}>
                    <div className="signal-info">
                      <span className="signal-name-full">{v.fullName}</span>
                      <span className="signal-details">타입: {v.type} | 비트 너비: {v.size}bit</span>
                    </div>
                    <div style={{ color: isSelected ? 'var(--accent-orange)' : 'var(--border-focus)' }}>
                      {isSelected ? '■ 선택됨' : '□ 해제됨'}
                    </div>
                  </div>
                );
              })}
              {filteredVars.length === 0 && (
                <div style={{ padding: '16px', textAlign: 'center', color: 'var(--text-muted)' }}>
                  검색 결과가 없습니다.
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
