import { useState, useRef } from 'react';
import { Sidebar } from './components/Sidebar';
import { Visualizer } from './components/Visualizer';
import { CodePreview } from './components/CodePreview';
import { DecoderCustomizer } from './components/DecoderCustomizer';
import { type SchedulerConfig, generateRTL, validateSchedulerConfig } from './utils/rtlGenerator';
import {
  type DecoderParamConfig,
  type InstructionFormat,
  type InstructionConfig,
  immediateExpression,
  generateDecoderRTL,
} from './utils/decoderGenerator';
import { downloadSourceBundle } from './utils/sourceBundle';

function App() {
  const [activeTab, setActiveTab] = useState<'core' | 'decoder'>('core');
  const [projectName, setProjectName] = useState('my_project');

  const [config, setConfig] = useState<SchedulerConfig>({
    decodeWidth: 2,
    phyRegs: 64,
    robEntries: 128,
    coresList: [
      { id: '1', name: 'Branch', count: 1, stroke: '#ff5500' },
      { id: '2', name: 'ALU', count: 3, stroke: '#00ccff' },
      { id: '3', name: 'Memory', count: 1, stroke: '#ffcc00' }
    ],
    prmUpdate: 3,
    prmBuffer: 4,
    unallocatePhyreg: 4,
    flowWindows: 8,
  });

  const [decoderConfig, setDecoderConfig] = useState<DecoderParamConfig>({
    instBitWidth: 32,
    instRegs: 32,
    instOperands: 2,
    instImm: 32,
    microopBitWidth: 5,
    isaName: 'rv32i',
  });

  const [formatsList, setFormatsList] = useState<InstructionFormat[]>([
    {
      id: 'fmt-r',
      name: 'R_type',
      fields: [
        { id: 'f-r-1', name: 'opcode', msb: 6, lsb: 0, role: 'Condition' },
        { id: 'f-r-2', name: 'rd', msb: 11, lsb: 7, role: 'rd' },
        { id: 'f-r-3', name: 'funct3', msb: 14, lsb: 12, role: 'Condition' },
        { id: 'f-r-4', name: 'rs1', msb: 19, lsb: 15, role: 'rs1' },
        { id: 'f-r-5', name: 'rs2', msb: 24, lsb: 20, role: 'rs2' },
        { id: 'f-r-6', name: 'funct7', msb: 31, lsb: 25, role: 'Condition' },
      ],
    },
    {
      id: 'fmt-i',
      name: 'I_type',
      fields: [
        { id: 'f-i-1', name: 'opcode', msb: 6, lsb: 0, role: 'Condition' },
        { id: 'f-i-2', name: 'rd', msb: 11, lsb: 7, role: 'rd' },
        { id: 'f-i-3', name: 'funct3', msb: 14, lsb: 12, role: 'Condition' },
        { id: 'f-i-4', name: 'rs1', msb: 19, lsb: 15, role: 'rs1' },
        { id: 'f-i-5', name: 'imm', msb: 31, lsb: 20, role: 'imm' },
      ],
    },
  ]);

  const [instructions, setInstructions] = useState<InstructionConfig[]>([
    {
      id: 'inst-add',
      name: 'ADD',
      formatId: 'fmt-r',
      conditions: {
        opcode: "7'b0110011",
        funct7: "7'b0000000",
        funct3: "3'b000",
      },
      exPathId: '2', // ALU
      microop: 1,
      newregAlloc: true,
      jump: false,
      jumpReg: false,
      branch: false,
    },
    {
      id: 'inst-sub',
      name: 'SUB',
      formatId: 'fmt-r',
      conditions: {
        opcode: "7'b0110011",
        funct7: "7'b0100000",
        funct3: "3'b000",
      },
      exPathId: '2', // ALU
      microop: 2,
      newregAlloc: true,
      jump: false,
      jumpReg: false,
      branch: false,
    },
    {
      id: 'inst-lw',
      name: 'LW',
      formatId: 'fmt-i',
      conditions: {
        opcode: "7'b0000011",
        funct3: "3'b010",
      },
      exPathId: '3', // Memory
      microop: 3,
      newregAlloc: true,
      jump: false,
      jumpReg: false,
      branch: false,
    },
  ]);

  // Validation function for the entire global CAD configuration schema
  const validateFullConfig = (data: unknown): data is {
    projectName?: string;
    scheduler: SchedulerConfig;
    decoder: DecoderParamConfig;
    formats: InstructionFormat[];
    instructions: InstructionConfig[];
  } => {
    const parsed = data as {
      projectName?: string;
      scheduler: SchedulerConfig;
      decoder: DecoderParamConfig;
      formats: InstructionFormat[];
      instructions: InstructionConfig[];
    };
    if (!data || typeof data !== 'object') return false;
    if (parsed.projectName !== undefined && typeof parsed.projectName !== 'string') return false;

    // 1. Scheduler Validation
    if (!parsed.scheduler || typeof parsed.scheduler !== 'object') return false;
    const schedParams = [
      'decodeWidth',
      'phyRegs',
      'robEntries',
      'coresList',
      'prmUpdate',
      'prmBuffer',
      'unallocatePhyreg',
      'flowWindows'
    ];
    for (const p of schedParams) {
      if (!(p in parsed.scheduler)) return false;
      if (p !== 'coresList' && typeof (parsed.scheduler as unknown as Record<string, unknown>)[p] !== 'number') return false;
    }
    if (!Array.isArray(parsed.scheduler.coresList)) return false;
    for (const core of parsed.scheduler.coresList) {
      if (!core || typeof core !== 'object') return false;
      if (
        typeof core.id !== 'string' ||
        typeof core.name !== 'string' ||
        typeof core.count !== 'number' ||
        typeof core.stroke !== 'string'
      ) return false;
    }

    // 2. Decoder Parameters Validation
    if (!parsed.decoder || typeof parsed.decoder !== 'object') return false;
    const decParams = ['instBitWidth', 'instRegs', 'instOperands', 'instImm', 'microopBitWidth'];
    for (const p of decParams) {
      if (!(p in parsed.decoder) || typeof (parsed.decoder as unknown as Record<string, unknown>)[p] !== 'number') return false;
    }
    if (typeof parsed.decoder.isaName !== 'string') return false;

    // 3. Formats Validation
    if (!Array.isArray(parsed.formats)) return false;
    for (const fmt of parsed.formats) {
      if (!fmt || typeof fmt !== 'object') return false;
      if (typeof fmt.id !== 'string' || typeof fmt.name !== 'string' || !Array.isArray(fmt.fields)) return false;
      for (const fd of fmt.fields) {
        if (!fd || typeof fd !== 'object') return false;
        if (
          typeof fd.id !== 'string' ||
          typeof fd.name !== 'string' ||
          typeof fd.msb !== 'number' ||
          typeof fd.lsb !== 'number' ||
          typeof fd.role !== 'string'
        ) return false;
      }
      if (fmt.signExtendImmediate !== undefined && typeof fmt.signExtendImmediate !== 'boolean') return false;
      if (fmt.immediateParts !== undefined) {
        if (!Array.isArray(fmt.immediateParts)) return false;
        for (const part of fmt.immediateParts) {
          if (!part || typeof part.id !== 'string' ||
              !Number.isInteger(part.sourceMsb) || !Number.isInteger(part.sourceLsb) ||
              !Number.isInteger(part.targetLsb)) return false;
        }
      }
    }

    // 4. Instructions Validation
    if (!Array.isArray(parsed.instructions)) return false;
    for (const inst of parsed.instructions) {
      if (!inst || typeof inst !== 'object') return false;
      const instFields = [
        'id',
        'name',
        'formatId',
        'conditions',
        'exPathId',
        'microop',
        'newregAlloc',
        'jump',
        'jumpReg',
        'branch'
      ];
      for (const f of instFields) {
        if (!(f in inst)) return false;
      }
      if (
        typeof inst.id !== 'string' ||
        typeof inst.name !== 'string' ||
        typeof inst.formatId !== 'string' ||
        typeof inst.conditions !== 'object' ||
        typeof inst.exPathId !== 'string' ||
        typeof inst.microop !== 'number' ||
        typeof inst.newregAlloc !== 'boolean' ||
        typeof inst.jump !== 'boolean' ||
        typeof inst.jumpReg !== 'boolean' ||
        typeof inst.branch !== 'boolean'
      ) return false;
    }

    return true;
  };

  const fileInputRef = useRef<HTMLInputElement>(null);

  // Serializes config, decoder, formats and instructions to eulsukdo_cad_config.json
  const handleExportJSON = () => {
    const fullConfig = {
      projectName,
      scheduler: config,
      decoder: decoderConfig,
      formats: formatsList,
      instructions: instructions
    };
    const dataStr = JSON.stringify(fullConfig, null, 2);
    const blob = new Blob([dataStr], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'eulsukdo_cad_config.json';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  };

  const handleTriggerImport = () => {
    fileInputRef.current?.click();
  };

  // Parses uploaded settings file and loads scheduler and decoder configs in parallel
  const handleImportJSON = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (event) => {
      try {
        const parsed = JSON.parse(event.target?.result as string);
        if (validateFullConfig(parsed)) {
          setProjectName(parsed.projectName ?? 'my_project');
          setConfig(parsed.scheduler);
          setDecoderConfig(parsed.decoder);
          setFormatsList(parsed.formats);
          setInstructions(parsed.instructions);
        } else {
          alert('Invalid EULSUKDO CAD configuration format. Please verify the JSON file structure.');
        }
      } catch {
        alert('Failed to parse JSON file. Ensure it is a valid JSON document.');
      }
    };
    reader.readAsText(file);
    e.target.value = ''; // Reset input to allow duplicate selection
  };

  const rtlConfig = { ...config, ...decoderConfig };
  const configError = validateSchedulerConfig(rtlConfig);
  const invalidImmediate = formatsList.find((fmt) => fmt.immediateParts?.length &&
    !immediateExpression(fmt, decoderConfig.instImm, decoderConfig.instBitWidth));
  const downloadError = configError || (invalidImmediate
    ? `${invalidImmediate.name} 즉시값 비트 범위가 겹치거나 유효하지 않습니다.` : null) ||
    (!projectName.trim() ? '프로젝트명을 입력해야 ZIP을 받을 수 있습니다.' : null);
  const generatedCode = configError ? '' : generateRTL(rtlConfig);
  const handleDownloadProject = () => {
    if (downloadError) return;
    const decoderCode = generateDecoderRTL(decoderConfig, formatsList, instructions, config.coresList);
    downloadSourceBundle(generatedCode, decoderCode, decoderConfig.isaName, projectName);
  };

  return (
    <>
      {/* SoundCloud Styled Top Header */}
      <header className="app-header" style={{ display: 'flex', alignItems: 'center' }}>
        <div className="logo-container" style={{ display: 'flex', alignItems: 'center' }}>
          <div className="sc-orange-bar" />
          <h1 className="app-title" style={{ margin: 0 }}>EULSUKDO CORE CAD</h1>
        </div>

        {/* Tab switcher buttons */}
        <div style={{ display: 'flex', gap: '8px', marginLeft: '32px' }}>
          <button
            className={`tab-btn ${activeTab === 'core' ? 'active' : ''}`}
            style={{
              background: 'transparent',
              border: 'none',
              borderBottom: activeTab === 'core' ? '2px solid var(--primary-orange)' : '2px solid transparent',
              color: activeTab === 'core' ? 'var(--primary-orange)' : '#888',
              padding: '8px 16px',
              fontSize: '12px',
              fontWeight: 'bold',
              cursor: 'pointer',
              textTransform: 'uppercase',
              transition: 'all 0.2s ease',
              boxShadow: activeTab === 'core' ? '0 0 10px rgba(255, 85, 0, 0.1)' : 'none',
            }}
            onClick={() => setActiveTab('core')}
          >
            Core Subsystem
          </button>
          <button
            className={`tab-btn ${activeTab === 'decoder' ? 'active' : ''}`}
            style={{
              background: 'transparent',
              border: 'none',
              borderBottom: activeTab === 'decoder' ? '2px solid var(--primary-orange)' : '2px solid transparent',
              color: activeTab === 'decoder' ? 'var(--primary-orange)' : '#888',
              padding: '8px 16px',
              fontSize: '12px',
              fontWeight: 'bold',
              cursor: 'pointer',
              textTransform: 'uppercase',
              transition: 'all 0.2s ease',
              boxShadow: activeTab === 'decoder' ? '0 0 10px rgba(255, 85, 0, 0.1)' : 'none',
            }}
            onClick={() => setActiveTab('decoder')}
          >
            Decoder Customizer
          </button>
        </div>

        <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: '12px' }}>
          <label className="project-name-field">
            <span>Project Name</span>
            <input
              type="text"
              value={projectName}
              maxLength={64}
              onChange={(e) => setProjectName(e.target.value)}
              placeholder="my_project"
              aria-label="Project Name"
            />
          </label>
          <div style={{ display: 'flex', gap: '6px' }}>
            <button
              className="btn"
              style={{ padding: '4px 10px', fontSize: '10px', borderColor: '#444', color: '#ccc', textTransform: 'uppercase', height: '26px', display: 'flex', alignItems: 'center' }}
              onClick={handleExportJSON}
              title="Export all CAD & Decoder settings to JSON"
            >
              Export
            </button>
            <button
              className="btn"
              style={{ padding: '4px 10px', fontSize: '10px', borderColor: '#444', color: '#ccc', textTransform: 'uppercase', height: '26px', display: 'flex', alignItems: 'center' }}
              onClick={handleTriggerImport}
              title="Import CAD & Decoder settings from JSON"
            >
              Import
            </button>
            <input
              type="file"
              ref={fileInputRef}
              style={{ display: 'none' }}
              accept=".json"
              onChange={handleImportJSON}
            />
          </div>
        </div>
      </header>

      {/* Conditional rendering based on the active tab */}
      {activeTab === 'core' ? (
        <main className="app-body">
          {/* Left Side: Parameters Slider Panel */}
          <Sidebar config={config} onChange={setConfig} />

          {/* Center: Dynamic Hardware Pipeline SVG Visualizer */}
          <Visualizer config={{ ...config, isaName: decoderConfig.isaName }} />

          {/* Right Side: Code Preview and file download triggers */}
          <div className="code-preview-wrapper">
            {downloadError && <div className="config-error">{downloadError}</div>}
            <CodePreview code={generatedCode} onDownloadProject={handleDownloadProject} downloadEnabled={!downloadError} />
          </div>
        </main>
      ) : (
        <DecoderCustomizer
          decConfig={decoderConfig}
          onChangeDecConfig={setDecoderConfig}
          formats={formatsList}
          onChangeFormats={setFormatsList}
          instructions={instructions}
          onChangeInstructions={setInstructions}
          coresList={config.coresList}
          onDownloadProject={handleDownloadProject}
          downloadEnabled={!downloadError}
          downloadError={downloadError}
        />
      )}
    </>
  );
}

export default App;
