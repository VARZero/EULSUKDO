import React, { useState } from 'react';
import { type SchedulerConfig } from '../utils/rtlGenerator';

interface VisualizerProps {
  config: SchedulerConfig;
}

interface HoverState {
  title: string;
  description: string;
  visible: boolean;
}

export const Visualizer: React.FC<VisualizerProps> = ({ config }) => {
  const [hoverInfo, setHoverInfo] = useState<HoverState>({
    title: '',
    description: '',
    visible: false,
  });

  const showTooltip = (title: string, description: string) => {
    setHoverInfo({ title, description, visible: true });
  };

  const hideTooltip = () => {
    setHoverInfo(prev => ({ ...prev, visible: false }));
  };

  // Helper variables for positioning
  const width = 800;
  const height = 550;

  // Render arrays based on config counts
  const decoders = Array(Math.min(config.decodeWidth, 8)).fill(0);

  // Dynamic layout calculations for Execution Cores
  const totalCores = config.coresList.reduce((sum, c) => sum + c.count, 0);
  const maxBoxWidth = 120;
  const gap = 10;
  const totalAvailableWidth = 560; // 600px wrapper width - 40px margins

  // Guard against zero cores
  const coreWidth = totalCores === 0 ? 0 : Math.min(maxBoxWidth, Math.floor((totalAvailableWidth - (totalCores - 1) * gap) / totalCores));
  const totalRowWidth = totalCores * coreWidth + (totalCores - 1) * gap;
  const startX = 100 + Math.floor((600 - totalRowWidth) / 2);

  // Flatten the cores list to draw individual boxes
  const coreDrawList = config.coresList.flatMap((core) => {
    return Array(core.count).fill(0).map((_, idx) => ({
      type: core.id,
      label: `${core.name}`,
      stroke: core.stroke,
      tooltipTitle: `${core.name} Core (Instance #${idx + 1})`,
      tooltipDesc: `'${core.name}' 기능 연산을 담당하는 비순차 실행 코어입니다. (이슈 경로 #${idx + 1})`
    }));
  });

  return (
    <div className="canvas-container">
      <div className="panel-header">
        <h2 className="panel-title">Pipeline Architecture</h2>
      </div>
      <div className="canvas-content">
        <svg className="svg-pipeline" viewBox={`0 0 ${width} ${height}`}>
          <defs>
            {/* Neon Orange glow filter in SoundCloud color */}
            <filter id="orange-glow" x="-20%" y="-20%" width="140%" height="140%">
              <feGaussianBlur stdDeviation="4" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
          </defs>

          {/* BACKGROUND BUS CONNECTORS (Animated orange glowing paths) */}
          {/* Main Feedback loop line from Execution Cores back to PRF */}
          <path
            d="M 400 480 L 100 480 L 100 240 L 220 240"
            className="flow-line flow-line-active"
            filter="url(#orange-glow)"
          />
          {/* Pipeline central paths */}
          <path d="M 400 65 L 400 120" className="flow-line flow-line-active" />
          <path d="M 400 160 L 400 220" className="flow-line flow-line-active" />
          <path d="M 400 260 L 400 320" className="flow-line flow-line-active" />
          <path d="M 400 365 L 400 400" className="flow-line flow-line-active" />

          {/* ==================== 1. FETCH STAGE ==================== */}
          <g
            onMouseEnter={() =>
              showTooltip(
                'Fetch Stage',
                `명령어 메모리로부터 한 사이클에 최대 ${config.decodeWidth}개의 명령어를 동시에 읽어와 디코더로 인출합니다.`
              )
            }
            onMouseLeave={hideTooltip}
          >
            <rect x="250" y="30" width="300" height="35" rx="3" className="pipeline-node pipeline-node-active" />
            <text x="400" y="48" className="node-text">Fetch Unit</text>
            <text x="400" y="58" className="node-subtext">{config.decodeWidth}-wide superscalar fetch</text>
          </g>

          {/* ==================== 2. DECODE STAGE ==================== */}
          {/* Outer box for Decode stage */}
          <g
            onMouseEnter={() =>
              showTooltip(
                `Decode Stage (${config.isaName ? config.isaName.toUpperCase() : 'Instruction'} Decoders)`,
                `인출된 명령어를 즉시 병렬 분석하여, 목적지 레지스터(rd), 소스 레지스터(rs1, rs2), 부호확장 즉시값(Immediate), 연산 분류(Micro-OP)를 추출합니다.`
              )
            }
            onMouseLeave={hideTooltip}
          >
            <rect x="180" y="120" width="440" height="40" rx="3" className="pipeline-node" strokeDasharray="4,4" style={{ fill: '#161616' }} />
            <text x="400" y="132" className="node-text" style={{ fill: '#8e8e93', fontSize: '10px' }}>DECODE STAGE</text>
          </g>

          {/* Individual Decoders */}
          {decoders.map((_, i) => {
            const decWidth = 360 / decoders.length;
            const startX = 400 - (180) + (i * (360 / decoders.length)) + (360 / decoders.length / 2) - (decWidth / 2 - 5);
            return (
              <rect
                key={i}
                x={startX}
                y={136}
                width={decWidth - 10}
                height={20}
                rx="2"
                className="pipeline-node pipeline-node-active"
                style={{ stroke: '#555555' }}
              />
            );
          })}

          {/* ==================== 3. RENAME & ALLOCATE STAGE ==================== */}
          <g
            onMouseEnter={() =>
              showTooltip(
                'Rename & Physical Register Mapping',
                `논리 레지스터(x0-x31)를 1사이클 비트맵 할당기로부터 추출한 가용 물리 레지스터(${config.phyRegs}개)로 이름 변경하여 RAW 의존성을 즉시 제거합니다.`
              )
            }
            onMouseLeave={hideTooltip}
          >
            <rect x="220" y="220" width="360" height="40" rx="3" className="pipeline-node" />
            <text x="400" y="235" className="node-text">Rename & Register Mapping (PRF)</text>
            <text x="400" y="250" className="node-subtext">
              FIFO Allocator ({config.phyRegs} registers)
            </text>
          </g>

          {/* ==================== 4. RESERVATION STATION (Issue Queue) ==================== */}
          <g
            onMouseEnter={() =>
              showTooltip(
                'Reservation Station (이슈 큐)',
                `정렬 완료된 명령어가 연산 대기하며, 소스 레지스터의 준비 여부(Ready 비트)가 완료되면, 해당 실행 장치로 즉시 비순차(Out-of-Order) 발행합니다.`
              )
            }
            onMouseLeave={hideTooltip}
          >
            <rect x="250" y="320" width="300" height="45" rx="3" className="pipeline-node pipeline-node-active" />
            <text x="400" y="338" className="node-text">Reservation Station (Issue Queue)</text>
            <text x="400" y="352" className="node-subtext">
              Unified Buffer / Entries: {config.robEntries}
            </text>
          </g>

          {/* ==================== 5. EXECUTION CORES ==================== */}
          {/* Wrapper bounds for Execution Stage */}
          <rect x="100" y="400" width="600" height="60" rx="3" className="pipeline-node" style={{ fill: '#141414', stroke: '#222222' }} />

          {totalCores > 0 ? (
            coreDrawList.map((core, idx) => {
              const cx = startX + idx * (coreWidth + gap);
              return (
                <g
                  key={`${core.type}-${idx}`}
                  onMouseEnter={() => showTooltip(core.tooltipTitle, core.tooltipDesc)}
                  onMouseLeave={hideTooltip}
                >
                  <rect
                    x={cx}
                    y={415}
                    width={coreWidth}
                    height={30}
                    rx="2"
                    className="pipeline-node pipeline-node-active"
                    style={{ stroke: core.stroke }}
                  />
                  <text x={cx + coreWidth / 2} y={430} className="node-text" style={{ fontSize: '9px' }}>
                    {core.label}
                  </text>
                </g>
              );
            })
          ) : (
            <text x="400" y="435" className="node-text" style={{ fill: '#ff3b30', fontSize: '10px' }}>
              Warning: No Execution Cores Defined! (RTL Compilation will fail)
            </text>
          )}

        </svg>

        {/* SoundCloud-Styled Tooltip Overlay */}
        <div className={`tooltip-card ${hoverInfo.visible ? 'visible' : ''}`}>
          <h4 className="tooltip-title">{hoverInfo.title}</h4>
          <p className="tooltip-desc">{hoverInfo.description}</p>
        </div>
      </div>
    </div>
  );
};
