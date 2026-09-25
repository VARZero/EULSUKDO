import React, { useRef, useEffect } from 'react';
import { type VcdData } from '../utils/vcdParser';

interface WaveformCanvasProps {
  vcdData: VcdData;
  selectedSignals: string[]; // ids of variables to display
  currentCycleIndex: number;
  onSelectCycle: (index: number) => void;
  zoomLevel: number;
  scrollLeft: number;
}

export const WaveformCanvas: React.FC<WaveformCanvasProps> = ({
  vcdData,
  selectedSignals,
  currentCycleIndex,
  onSelectCycle,
  zoomLevel,
  scrollLeft,
}) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);

  const signalHeight = 44;
  const signalPadding = 12;
  const timelineHeight = 32;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Set canvas dimensions
    const width = containerRef.current?.clientWidth || 800;
    const height = Math.max(timelineHeight + selectedSignals.length * (signalHeight + signalPadding), 200);
    canvas.width = width;
    canvas.height = height;

    // Clear canvas
    ctx.fillStyle = '#0a0a0a';
    ctx.fillRect(0, 0, width, height);

    if (vcdData.timeline.length === 0) return;

    // Setup timeline metrics
    const totalDuration = vcdData.timeline[vcdData.timeline.length - 1] - vcdData.timeline[0];
    const timeScaleFactor = (width * 0.8 * zoomLevel) / (totalDuration || 1);

    const getX = (ts: number): number => {
      return (ts - vcdData.timeline[0]) * timeScaleFactor - scrollLeft + 180;
    };

    // Draw grid & timeline background
    ctx.fillStyle = '#121212';
    ctx.fillRect(180, 0, width - 180, timelineHeight);
    ctx.strokeStyle = '#262626';
    ctx.beginPath();
    ctx.moveTo(180, timelineHeight);
    ctx.lineTo(width, timelineHeight);
    ctx.moveTo(180, 0);
    ctx.lineTo(180, height);
    ctx.stroke();

    // Draw clock ticks / timeline ticks
    ctx.fillStyle = '#8a8a8a';
    ctx.font = '10px ui-monospace, monospace';
    ctx.textAlign = 'center';

    // Draw vertical timeline gridlines
    const tickInterval = Math.max(10, Math.ceil(totalDuration / (10 * zoomLevel)));
    for (let t = vcdData.timeline[0]; t <= vcdData.timeline[vcdData.timeline.length - 1]; t += tickInterval) {
      const x = getX(t);
      if (x >= 180 && x <= width) {
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
        ctx.beginPath();
        ctx.moveTo(x, timelineHeight);
        ctx.lineTo(x, height);
        ctx.stroke();

        ctx.strokeStyle = '#404040';
        ctx.beginPath();
        ctx.moveTo(x, timelineHeight - 8);
        ctx.lineTo(x, timelineHeight);
        ctx.stroke();

        ctx.fillText(`${t} ${vcdData.timescale}`, x, 18);
      }
    }

    // Draw each signal wave
    selectedSignals.forEach((sigId, index) => {
      const variable = vcdData.varsById[sigId];
      if (!variable) return;

      const yOffset = timelineHeight + index * (signalHeight + signalPadding) + signalPadding;

      // Signal Label sidebar background
      ctx.fillStyle = '#121212';
      ctx.fillRect(0, yOffset - signalPadding / 2, 180, signalHeight + signalPadding);
      ctx.strokeStyle = '#262626';
      ctx.beginPath();
      ctx.moveTo(0, yOffset + signalHeight + signalPadding / 2);
      ctx.lineTo(width, yOffset + signalHeight + signalPadding / 2);
      ctx.stroke();

      // Signal text label
      ctx.fillStyle = '#ffffff';
      ctx.font = '11px ui-monospace, monospace';
      ctx.textAlign = 'left';
      ctx.fillText(variable.name, 12, yOffset + 18);

      ctx.fillStyle = '#8a8a8a';
      ctx.font = '9px system-ui';
      ctx.fillText(variable.fullName.substring(0, variable.fullName.lastIndexOf('.')), 12, yOffset + 32);

      // Render the digital waveform path
      ctx.lineWidth = 1.5;
      ctx.strokeStyle = '#ff5500';
      ctx.fillStyle = 'rgba(255, 85, 0, 0.04)';

      let lastX = getX(vcdData.timeline[0]);
      let lastVal = vcdData.changes[vcdData.timeline[0]]?.[sigId] || 'x';

      ctx.beginPath();
      if (variable.size === 1) {
        // Draw binary digital wave
        const drawY = (val: string) => {
          if (val === '1') return yOffset + 6;
          if (val === '0') return yOffset + signalHeight - 6;
          return yOffset + signalHeight / 2; // 'x' or 'z'
        };

        ctx.moveTo(Math.max(180, lastX), drawY(lastVal));

        for (let tIdx = 1; tIdx < vcdData.timeline.length; tIdx++) {
          const ts = vcdData.timeline[tIdx];
          const nextX = getX(ts);

          // Use every VCD timestamp, including changes between rising edges.
          const nextVal = vcdData.changes[ts]?.[sigId] || lastVal;

          if (nextX >= 180) {
            // Draw horizontal line
            ctx.lineTo(nextX, drawY(lastVal));
            // Draw vertical transition line
            if (nextVal !== lastVal) {
              ctx.lineTo(nextX, drawY(nextVal));
            }
          } else {
            ctx.moveTo(180, drawY(nextVal));
          }

          lastX = nextX;
          lastVal = nextVal;
        }
        // draw to edge
        ctx.lineTo(width, drawY(lastVal));
        ctx.stroke();
      } else {
        // Draw multi-bit bus wave (hexagonal boxes)
        ctx.beginPath();
        for (let tIdx = 0; tIdx < vcdData.timeline.length; tIdx++) {
          const ts = vcdData.timeline[tIdx];
          const nextTs = vcdData.timeline[tIdx + 1] || vcdData.timeline[vcdData.timeline.length - 1] + 10;
          const startX = Math.max(180, getX(ts));
          const endX = Math.max(180, getX(nextTs));

          if (startX >= width) break;
          if (endX < 180) continue;

          const val = vcdData.changes[ts]?.[sigId] || lastVal;

          // Format value to hex
          let hexDisplay = val;
          if (val && !val.includes('x') && !val.includes('z')) {
            try {
              hexDisplay = parseInt(val, 2).toString(16).toUpperCase();
            } catch {
              hexDisplay = val;
            }
          }

          // Draw bus box
          ctx.strokeStyle = '#00ccff';
          ctx.fillStyle = 'rgba(0, 204, 255, 0.03)';
          ctx.beginPath();
          ctx.moveTo(startX, yOffset + 6);
          ctx.lineTo(endX, yOffset + 6);
          ctx.lineTo(endX - 3, yOffset + signalHeight - 6);
          ctx.lineTo(startX + 3, yOffset + signalHeight - 6);
          ctx.closePath();
          ctx.stroke();
          ctx.fill();

          // Draw bus label
          if (endX - startX > 30) {
            ctx.fillStyle = '#00ccff';
            ctx.font = '10px ui-monospace, monospace';
            ctx.textAlign = 'center';
            ctx.fillText(hexDisplay, startX + (endX - startX) / 2, yOffset + signalHeight / 2 + 3);
          }

          lastVal = val;
        }
      }
    });

    // Draw current cycle cursor (red line)
    const selectedCycle = vcdData.cycles[Math.min(currentCycleIndex, vcdData.cycles.length - 1)];
    if (selectedCycle) {
      const cursorX = getX(selectedCycle.timestamp);
      if (cursorX >= 180 && cursorX <= width) {
        ctx.strokeStyle = '#ff003c';
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        ctx.moveTo(cursorX, timelineHeight);
        ctx.lineTo(cursorX, height);
        ctx.stroke();

        // Draw cursor handle at top
        ctx.fillStyle = '#ff003c';
        ctx.beginPath();
        ctx.arc(cursorX, timelineHeight, 4, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }, [vcdData, selectedSignals, currentCycleIndex, zoomLevel, scrollLeft]);

  // Click on waveform to jump cycles
  const handleCanvasClick = (e: React.MouseEvent<HTMLCanvasElement>) => {
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect) return;
    const x = e.clientX - rect.left;
    if (x < 180) return; // Ignore click on signal label area

    // Calculate time based on x
    const canvasWidth = canvasRef.current?.width || 800;
    const totalDuration = vcdData.timeline[vcdData.timeline.length - 1] - vcdData.timeline[0];
    const timeScaleFactor = (canvasWidth * 0.8 * zoomLevel) / (totalDuration || 1);
    const clickedTime = (x - 180 + scrollLeft) / timeScaleFactor + vcdData.timeline[0];

    // Find closest cycle
    let closestIndex = 0;
    let minDiff = Infinity;
    vcdData.cycles.forEach((c, idx) => {
      const diff = Math.abs(c.timestamp - clickedTime);
      if (diff < minDiff) {
        minDiff = diff;
        closestIndex = idx;
      }
    });

    onSelectCycle(closestIndex);
  };

  return (
    <div ref={containerRef} className="waveform-canvas-wrapper" style={{ overflowX: 'auto', flex: 1 }}>
      <canvas
        ref={canvasRef}
        className="waveform-canvas"
        onClick={handleCanvasClick}
        style={{ cursor: 'col-resize' }}
      />
    </div>
  );
};
