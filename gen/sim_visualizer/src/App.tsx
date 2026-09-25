import { useState, useEffect, useRef } from 'react';
import './App.css';
import { LeftPanel } from './components/LeftPanel';
import { TopRightPanel } from './components/TopRightPanel';
import { BottomRightPanel } from './components/BottomRightPanel';
import { parseVcd, type VcdData } from './utils/vcdParser';

function App() {
  const [config, setConfig] = useState<any>({
    scheduler: {
      decodeWidth: 2,
      phyRegs: 64,
      robEntries: 128,
      coresList: [
        { id: '1', name: 'Branch', count: 1, stroke: '#ff5500' },
        { id: '2', name: 'ALU', count: 3, stroke: '#00ccff' },
        { id: '3', name: 'Memory', count: 1, stroke: '#ffcc00' }
      ]
    }
  });

  const [vcdData, setVcdData] = useState<VcdData | null>(null);
  const [currentCycleIndex, setCurrentCycleIndex] = useState<number>(0);
  const [selectedModule, setSelectedModule] = useState<string>('nel');
  const [isPlaying, setIsPlaying] = useState<boolean>(false);
  const [playSpeedMs, setPlaySpeedMs] = useState<number>(500); // interval duration

  const playTimerRef = useRef<any>(null);

  // Playback timer effect
  useEffect(() => {
    if (isPlaying && vcdData && vcdData.cycles.length > 0) {
      playTimerRef.current = setInterval(() => {
        setCurrentCycleIndex(prev => {
          if (prev >= vcdData.cycles.length - 1) {
            setIsPlaying(false);
            return prev;
          }
          return prev + 1;
        });
      }, playSpeedMs);
    } else {
      if (playTimerRef.current) {
        clearInterval(playTimerRef.current);
      }
    }

    return () => {
      if (playTimerRef.current) {
        clearInterval(playTimerRef.current);
      }
    };
  }, [isPlaying, vcdData, playSpeedMs]);

  // Load a real trace captured from gen/src/TB_UVM/tb_eulsukdo_scheduler.sv
  const handleLoadSample = async () => {
    try {
      const response = await fetch(`${import.meta.env.BASE_URL}gen_sample.vcd`);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const parsed = parseVcd(await response.text());
      if (parsed.cycles.length === 0) throw new Error('No samples in VCD');
      setConfig({ scheduler: {
        decodeWidth: 2, phyRegs: 64, robEntries: 128,
        coresList: [
          { id: '1', name: 'Branch', count: 1, stroke: '#ff5500' },
          { id: '2', name: 'ALU', count: 3, stroke: '#00ccff' },
          { id: '3', name: 'Memory', count: 1, stroke: '#ffcc00' },
        ],
      } });
      setVcdData(parsed);
      setCurrentCycleIndex(0);
      setIsPlaying(false);
    } catch (error) {
      alert(`Gen VCD 로드 실패: ${(error as Error).message}`);
    }
  };

  // Upload JSON config
  const handleJsonUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (event) => {
      try {
        const parsed = JSON.parse(event.target?.result as string);
        if (parsed.scheduler) {
          setConfig(parsed);
          alert('CAD 구조 설정 파일을 성공적으로 불러왔습니다.');
        } else {
          alert('올바른 Eulsukdo CAD 설정 JSON 형식이 아닙니다.');
        }
      } catch (err) {
        alert('JSON 파싱 오류가 발생했습니다: ' + (err as Error).message);
      }
    };
    reader.readAsText(file);
  };

  // Upload VCD file
  const handleVcdUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (event) => {
      try {
        const vcdText = event.target?.result as string;
        const parsed = parseVcd(vcdText);
        if (parsed.vars.length === 0) throw new Error('VCD signal definitions not found');
        setVcdData(parsed);
        setCurrentCycleIndex(0);
        setIsPlaying(false);
        alert('VCD 시뮬레이션 데이터를 성공적으로 불러왔습니다. 총 ' + parsed.cycles.length + ' 사이클이 탐지되었습니다.');
      } catch (err) {
        alert('VCD 파싱 오류가 발생했습니다: ' + (err as Error).message);
      }
    };
    reader.readAsText(file);
  };

  // Playback control helpers
  const handleStepForward = () => {
    if (vcdData && currentCycleIndex < vcdData.cycles.length - 1) {
      setCurrentCycleIndex(prev => prev + 1);
    }
  };

  const handleStepBackward = () => {
    if (currentCycleIndex > 0) {
      setCurrentCycleIndex(prev => prev - 1);
    }
  };

  const handleJumpToStart = () => {
    setCurrentCycleIndex(0);
  };

  const handleJumpToEnd = () => {
    if (vcdData) {
      setCurrentCycleIndex(vcdData.cycles.length - 1);
    }
  };

  const maxCycles = vcdData ? vcdData.cycles.length - 1 : 0;

  return (
    <div className="app-container">
      {/* Header bar with controls */}
      <header className="app-header">
        <div className="brand-section">
          <span className="brand-logo">EULSUKDO</span>
          <span className="brand-badge">Sim Visualizer</span>
        </div>

        <div className="controls-section">
          {/* File Uploads */}
          <div className="file-upload-group">
            <label className="file-label" title="CAD 생성기에서 다운로드한 JSON 설정 파일을 가져옵니다.">
              📁 Gen 구조 JSON 업로드
              <input type="file" accept=".json" className="file-input" onChange={handleJsonUpload} />
            </label>
            <label className="file-label" title="테스트벤치(Verilator/Icarus)에서 출력한 VCD 파일을 가져옵니다.">
              ⚡ VCD 파형 업로드
              <input type="file" accept=".vcd" className="file-input" onChange={handleVcdUpload} />
            </label>
          </div>

          {/* Timeline & Playback controls */}
          <div className="playback-controls">
            <button className="control-btn" onClick={handleJumpToStart} title="처음 사이클로 이동">
              ⏮
            </button>
            <button className="control-btn" onClick={handleStepBackward} title="이전 사이클 (1단계)">
              ◀
            </button>
            <button
              className={`control-btn ${isPlaying ? 'active' : ''}`}
              onClick={() => setIsPlaying(!isPlaying)}
              title={isPlaying ? '일시정지' : '자동 재생'}
            >
              {isPlaying ? '⏸' : '▶'}
            </button>
            <button className="control-btn" onClick={handleStepForward} title="다음 사이클 (1단계)">
              ▶
            </button>
            <button className="control-btn" onClick={handleJumpToEnd} title="마지막 사이클로 이동">
              ⏭
            </button>
          </div>

          {/* Speed selector */}
          <select
            value={playSpeedMs}
            onChange={(e) => setPlaySpeedMs(Number(e.target.value))}
            style={{
              backgroundColor: 'var(--bg-tertiary)',
              border: '1px solid var(--border-color)',
              color: 'var(--text-secondary)',
              padding: '6px',
              borderRadius: '4px',
              fontSize: '11px',
              outline: 'none'
            }}
            title="자동 재생 속도 설정"
          >
            <option value={1000}>1.0초 간격</option>
            <option value={500}>0.5초 간격</option>
            <option value={200}>0.2초 간격</option>
            <option value={100}>0.1초 간격</option>
          </select>

          {/* Cycle Slider */}
          <div className="cycle-slider-container">
            <input
              type="range"
              min={0}
              max={maxCycles}
              value={currentCycleIndex}
              onChange={(e) => {
                setCurrentCycleIndex(Number(e.target.value));
                setIsPlaying(false);
              }}
              className="cycle-slider"
              disabled={!vcdData}
            />
            <span className="cycle-display">
              {vcdData ? `CYCLE ${currentCycleIndex} / ${maxCycles}` : 'WAITING VCD...'}
            </span>
          </div>
        </div>

        <div className="meta-section">
          <button className="btn-sample" onClick={handleLoadSample}>
            ⚡ Gen 테스트 VCD 로드
          </button>
        </div>
      </header>

      {/* Main 3-Panel Layout */}
      <main className="main-layout">
        {/* Left: Interactive Diagram */}
        <LeftPanel
          selectedModule={selectedModule}
          onSelectModule={setSelectedModule}
          vcdData={vcdData}
          currentCycleIndex={currentCycleIndex}
        />

        {/* Right Columns */}
        <div className="right-container">
          {/* Top Right: Selected Module Details */}
          <TopRightPanel
            selectedModule={selectedModule}
            vcdData={vcdData}
            currentCycleIndex={currentCycleIndex}
            config={config}
          />

          {/* Bottom Right: Timing Waveform */}
          <BottomRightPanel
            selectedModule={selectedModule}
            vcdData={vcdData}
            currentCycleIndex={currentCycleIndex}
            onSelectCycle={setCurrentCycleIndex}
          />
        </div>
      </main>
    </div>
  );
}

export default App;
