import React, { useState, useMemo } from 'react';
import {
  type DecoderParamConfig,
  type InstructionFormat,
  type InstructionConfig,
  type FormatField,
  type ImmediatePart,
  type FieldRole,
  generateDecoderRTL,
} from '../utils/decoderGenerator';
import { type CoreTypeConfig } from '../utils/rtlGenerator';

interface DecoderCustomizerProps {
  decConfig: DecoderParamConfig;
  onChangeDecConfig: (c: DecoderParamConfig) => void;
  formats: InstructionFormat[];
  onChangeFormats: (f: InstructionFormat[]) => void;
  instructions: InstructionConfig[];
  onChangeInstructions: (i: InstructionConfig[]) => void;
  coresList: CoreTypeConfig[];
  onDownloadProject: () => void;
  downloadEnabled: boolean;
  downloadError: string | null;
}

export const DecoderCustomizer: React.FC<DecoderCustomizerProps> = ({
  decConfig,
  onChangeDecConfig,
  formats,
  onChangeFormats,
  instructions,
  onChangeInstructions,
  coresList,
  onDownloadProject,
  downloadEnabled,
  downloadError,
}) => {
  const [activeFormatId, setActiveFormatId] = useState<string | null>(formats[0]?.id || null);
  const [copied, setCopied] = useState(false);

  const updateParam = (key: keyof DecoderParamConfig, val: number) => {
    onChangeDecConfig({
      ...decConfig,
      [key]: val,
    });
  };

  // --- Format Customizer Helpers ---
  const handleAddFormat = () => {
    const newFmt: InstructionFormat = {
      id: `fmt-${Date.now()}`,
      name: `Format_${formats.length + 1}`,
      fields: [
        { id: `f-${Date.now()}-1`, name: 'opcode', msb: 6, lsb: 0, role: 'Condition' },
        { id: `f-${Date.now()}-2`, name: 'rd', msb: 11, lsb: 7, role: 'rd' },
      ],
    };
    onChangeFormats([...formats, newFmt]);
    setActiveFormatId(newFmt.id);
  };

  const handleRemoveFormat = (id: string) => {
    if (formats.length <= 1) return;
    onChangeFormats(formats.filter((f) => f.id !== id));
    if (activeFormatId === id) {
      setActiveFormatId(formats.find((f) => f.id !== id)?.id || null);
    }
  };

  const handleUpdateFormatName = (id: string, name: string) => {
    onChangeFormats(
      formats.map((f) => (f.id === id ? { ...f, name: name.replace(/\s+/g, '_') } : f))
    );
  };

  const handleAddImmediatePart = (formatId: string) => {
    onChangeFormats(formats.map((fmt) => fmt.id === formatId ? {
      ...fmt,
      immediateParts: [...(fmt.immediateParts || []), {
        id: `imm-${Date.now()}`, sourceMsb: 31, sourceLsb: 20, targetLsb: 0,
      }],
    } : fmt));
  };

  const handleUpdateImmediatePart = (formatId: string, partId: string,
    key: keyof ImmediatePart, value: number) => {
    onChangeFormats(formats.map((fmt) => fmt.id === formatId ? {
      ...fmt,
      immediateParts: (fmt.immediateParts || []).map((part) =>
        part.id === partId ? { ...part, [key]: value } : part),
    } : fmt));
  };

  const handleRemoveImmediatePart = (formatId: string, partId: string) => {
    onChangeFormats(formats.map((fmt) => fmt.id === formatId ? {
      ...fmt,
      immediateParts: (fmt.immediateParts || []).filter((part) => part.id !== partId),
    } : fmt));
  };

  const handleAddField = (fmtId: string) => {
    onChangeFormats(
      formats.map((f) => {
        if (f.id === fmtId) {
          const newField: FormatField = {
            id: `f-${Date.now()}`,
            name: `field_${f.fields.length + 1}`,
            msb: 31,
            lsb: 25,
            role: 'None',
          };
          return { ...f, fields: [...f.fields, newField] };
        }
        return f;
      })
    );
  };

  const handleRemoveField = (fmtId: string, fieldId: string) => {
    onChangeFormats(
      formats.map((f) => {
        if (f.id === fmtId) {
          return { ...f, fields: f.fields.filter((fd) => fd.id !== fieldId) };
        }
        return f;
      })
    );
  };

  const handleUpdateField = (
    fmtId: string,
    fieldId: string,
    key: keyof FormatField,
    val: string | number
  ) => {
    onChangeFormats(
      formats.map((f) => {
        if (f.id === fmtId) {
          return {
            ...f,
            fields: f.fields.map((fd) => (fd.id === fieldId ? { ...fd, [key]: val } : fd)),
          };
        }
        return f;
      })
    );
  };

  // --- Instruction Helpers ---
  const handleAddInstruction = () => {
    const defaultFmt = formats[0];
    if (!defaultFmt) return;

    // Build default condition map
    const defaultConds: Record<string, string> = {};
    defaultFmt.fields.forEach((fd) => {
      if (fd.role === 'Condition') {
        defaultConds[fd.name] = "7'b0000000";
      }
    });

    const newInst: InstructionConfig = {
      id: `inst-${Date.now()}`,
      name: `INST_${instructions.length + 1}`,
      formatId: defaultFmt.id,
      conditions: defaultConds,
      exPathId: coresList[0]?.id || '1',
      microop: instructions.length + 1,
      newregAlloc: true,
      jump: false,
      jumpReg: false,
      branch: false,
    };
    onChangeInstructions([...instructions, newInst]);
  };

  const handleRemoveInstruction = (id: string) => {
    onChangeInstructions(instructions.filter((inst) => inst.id !== id));
  };

  const handleUpdateInstruction = (id: string, key: keyof InstructionConfig, val: InstructionConfig[keyof InstructionConfig]) => {
    onChangeInstructions(
      instructions.map((inst) => (inst.id === id ? { ...inst, [key]: val } : inst))
    );
  };

  const handleUpdateInstructionCondition = (
    instId: string,
    fieldName: string,
    matchValue: string
  ) => {
    onChangeInstructions(
      instructions.map((inst) => {
        if (inst.id === instId) {
          return {
            ...inst,
            conditions: {
              ...inst.conditions,
              [fieldName]: matchValue,
            },
          };
        }
        return inst;
      })
    );
  };

  // Generate RTL code
  const generatedCode = useMemo(() => {
    return generateDecoderRTL(decConfig, formats, instructions, coresList);
  }, [decConfig, formats, instructions, coresList]);

  const activeFormat = formats.find((f) => f.id === activeFormatId);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(generatedCode);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (err) {
      console.error('Failed to copy: ', err);
    }
  };

  return (
    <main className="app-body" style={{ display: 'grid', gridTemplateColumns: '320px 1fr 400px', gap: '16px', height: 'calc(100vh - 70px)', overflow: 'hidden' }}>

      {/* 1. Left Sidebar: Decoder Params & Formats builder */}
      <div className="panel sidebar" style={{ overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '12px', height: '100%' }}>
        <div className="panel-header">
          <h2 className="panel-title">Decoder Parameters</h2>
        </div>

        <div className="sidebar-content" style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
          {/* ISA Name Input */}
          <div className="form-group">
            <label className="form-label">
              <span>ISA Name (Prefix)</span>
            </label>
            <input
              type="text"
              style={{
                backgroundColor: '#1e1e1e',
                border: '1px solid var(--border-color)',
                color: 'var(--text-main)',
                padding: '8px 12px',
                fontSize: '13px',
                outline: 'none',
                borderRadius: '2px'
              }}
              value={decConfig.isaName}
              onChange={(e) => onChangeDecConfig({ ...decConfig, isaName: e.target.value.toLowerCase().replace(/\s+/g, '') })}
              placeholder="e.g. rv32i, mips, custom"
            />
          </div>

          {/* Inst bit width */}
          <div className="form-group">
            <label className="form-label">
              <span>Instruction Length</span>
              <span className="form-value">{decConfig.instBitWidth} bits</span>
            </label>
            <input
              type="number"
              min="16"
              max="64"
              value={decConfig.instBitWidth}
              onChange={(e) => updateParam('instBitWidth', parseInt(e.target.value) || 32)}
            />
          </div>

          {/* GPR registers */}
          <div className="form-group">
            <label className="form-label">
              <span>Logic GPR Registers</span>
              <span className="form-value">{decConfig.instRegs} regs</span>
            </label>
            <input
              type="number"
              min="4"
              max="64"
              value={decConfig.instRegs}
              onChange={(e) => updateParam('instRegs', parseInt(e.target.value) || 32)}
            />
          </div>

          {/* Operands per Instruction */}
          <div className="form-group">
            <label className="form-label">
              <span>Max Operands / GPR</span>
              <span className="form-value">{decConfig.instOperands}</span>
            </label>
            <input
              type="number"
              min="1"
              max="4"
              value={decConfig.instOperands}
              onChange={(e) => updateParam('instOperands', parseInt(e.target.value) || 2)}
            />
          </div>

          {/* Immediate width */}
          <div className="form-group">
            <label className="form-label">
              <span>Immediate Width</span>
              <span className="form-value">{decConfig.instImm} bits</span>
            </label>
            <input
              type="number"
              min="4"
              max="64"
              value={decConfig.instImm}
              onChange={(e) => updateParam('instImm', parseInt(e.target.value) || 32)}
            />
          </div>

          <div style={{ height: '1px', backgroundColor: '#222', margin: '4px 0' }} />

          {/* FORMATS SECTION */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span style={{ fontSize: '11px', fontWeight: 'bold', textTransform: 'uppercase', color: '#888' }}>Custom Formats</span>
            <button className="btn" style={{ padding: '2px 6px', fontSize: '9px' }} onClick={handleAddFormat}>
              + Add
            </button>
          </div>

          {/* Tab selector for active format */}
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px' }}>
            {formats.map((fmt) => (
              <button
                key={fmt.id}
                className="btn"
                style={{
                  padding: '4px 8px',
                  fontSize: '10px',
                  backgroundColor: activeFormatId === fmt.id ? 'var(--primary-orange)' : '#161616',
                  color: activeFormatId === fmt.id ? '#000' : '#888',
                  borderColor: activeFormatId === fmt.id ? 'var(--primary-orange)' : '#333',
                  fontWeight: activeFormatId === fmt.id ? 'bold' : 'normal',
                }}
                onClick={() => setActiveFormatId(fmt.id)}
              >
                {fmt.name}
              </button>
            ))}
          </div>

          {activeFormat && (
            <div style={{ border: '1px solid #222', padding: '10px', backgroundColor: '#111', display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontSize: '10px', color: '#ff5500', fontWeight: 'bold' }}>Format Settings</span>
                {formats.length > 1 && (
                  <button
                    className="btn"
                    style={{ padding: '1px 5px', fontSize: '9px', borderColor: '#ff2d55', color: '#ff2d55' }}
                    onClick={() => handleRemoveFormat(activeFormat.id)}
                  >
                    Delete Fmt
                  </button>
                )}
              </div>

              <div className="form-group">
                <label style={{ fontSize: '9px', color: '#888' }}>Format Name</label>
                <input
                  type="text"
                  style={{ backgroundColor: '#0c0c0c', border: '1px solid #222', color: '#eee', padding: '3px 6px', fontSize: '11px' }}
                  value={activeFormat.name}
                  onChange={(e) => handleUpdateFormatName(activeFormat.id, e.target.value)}
                />
              </div>

              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontSize: '9px', fontWeight: 'bold', color: '#888' }}>Immediate Bit Mapping</span>
                <button className="btn" style={{ padding: '1px 4px', fontSize: '8px' }}
                  onClick={() => handleAddImmediatePart(activeFormat.id)}>+ Add Part</button>
              </div>
              <label style={{ fontSize: '9px', color: '#888' }}>
                <input type="checkbox" checked={!!activeFormat.signExtendImmediate}
                  onChange={(e) => onChangeFormats(formats.map((fmt) => fmt.id === activeFormat.id
                    ? { ...fmt, signExtendImmediate: e.target.checked } : fmt))} /> Sign extend upper bits
              </label>
              {(activeFormat.immediateParts || []).map((part) => (
                <div key={part.id} style={{ display: 'flex', alignItems: 'center', gap: '4px', fontSize: '9px' }}>
                  <span>inst[</span>
                  <input aria-label="Source MSB" type="number" min="0" max={decConfig.instBitWidth - 1}
                    style={{ width: '38px', backgroundColor: '#0c0c0c', border: '1px solid #333', color: '#eee', padding: '3px' }} value={part.sourceMsb}
                    onChange={(e) => handleUpdateImmediatePart(activeFormat.id, part.id, 'sourceMsb', Number(e.target.value))} />
                  <span>:</span>
                  <input aria-label="Source LSB" type="number" min="0" max={decConfig.instBitWidth - 1}
                    style={{ width: '38px', backgroundColor: '#0c0c0c', border: '1px solid #333', color: '#eee', padding: '3px' }} value={part.sourceLsb}
                    onChange={(e) => handleUpdateImmediatePart(activeFormat.id, part.id, 'sourceLsb', Number(e.target.value))} />
                  <span>] → imm[</span>
                  <input aria-label="Immediate LSB" type="number" min="0" max={decConfig.instImm - 1}
                    style={{ width: '38px', backgroundColor: '#0c0c0c', border: '1px solid #333', color: '#eee', padding: '3px' }} value={part.targetLsb}
                    onChange={(e) => handleUpdateImmediatePart(activeFormat.id, part.id, 'targetLsb', Number(e.target.value))} />
                  <span>+:]</span>
                  <button aria-label="Remove immediate part" style={{ background: 'transparent', border: 'none', color: '#ff2d55' }}
                    onClick={() => handleRemoveImmediatePart(activeFormat.id, part.id)}>✕</button>
                </div>
              ))}
              <span style={{ fontSize: '9px', color: '#666' }}>윗부분은 부호 확장 또는 0으로 채웁니다. 비어 있으면 기존 imm 필드를 사용합니다.</span>

              {/* Fields List */}
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '4px' }}>
                <span style={{ fontSize: '9px', fontWeight: 'bold', color: '#888' }}>Fields Layout</span>
                <button className="btn" style={{ padding: '1px 4px', fontSize: '8px' }} onClick={() => handleAddField(activeFormat.id)}>
                  + Add Field
                </button>
              </div>

              <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', maxHeight: '200px', overflowY: 'auto', paddingRight: '2px' }}>
                {activeFormat.fields.map((field) => (
                  <div
                    key={field.id}
                    style={{
                      border: '1px solid #1c1c1c',
                      padding: '6px',
                      backgroundColor: '#0c0c0c',
                      display: 'flex',
                      flexDirection: 'column',
                      gap: '4px',
                    }}
                  >
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                      <input
                        type="text"
                        style={{
                          backgroundColor: 'transparent',
                          border: 'none',
                          borderBottom: '1px solid #333',
                          color: '#fff',
                          fontSize: '10px',
                          padding: '1px',
                          width: '80px',
                        }}
                        value={field.name}
                        onChange={(e) => handleUpdateField(activeFormat.id, field.id, 'name', e.target.value.replace(/\s+/g, '_'))}
                      />
                      <button
                        style={{ background: 'transparent', border: 'none', color: '#ff2d55', fontSize: '10px', cursor: 'pointer' }}
                        onClick={() => handleRemoveField(activeFormat.id, field.id)}
                      >
                        ✕
                      </button>
                    </div>

                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '4px' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '3px' }}>
                        <span style={{ fontSize: '8px', color: '#666' }}>MSB:</span>
                        <input
                          type="number"
                          style={{ width: '40px', backgroundColor: '#181818', border: '1px solid #222', color: '#fff', fontSize: '9px', padding: '1px 3px' }}
                          value={field.msb}
                          onChange={(e) => handleUpdateField(activeFormat.id, field.id, 'msb', parseInt(e.target.value) || 0)}
                        />
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '3px' }}>
                        <span style={{ fontSize: '8px', color: '#666' }}>LSB:</span>
                        <input
                          type="number"
                          style={{ width: '40px', backgroundColor: '#181818', border: '1px solid #222', color: '#fff', fontSize: '9px', padding: '1px 3px' }}
                          value={field.lsb}
                          onChange={(e) => handleUpdateField(activeFormat.id, field.id, 'lsb', parseInt(e.target.value) || 0)}
                        />
                      </div>
                    </div>

                    <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                      <span style={{ fontSize: '8px', color: '#666' }}>Role:</span>
                      <select
                        style={{
                          backgroundColor: '#181818',
                          border: '1px solid #222',
                          color: '#aaa',
                          fontSize: '9px',
                          padding: '1px',
                          width: '100%',
                        }}
                        value={field.role}
                        onChange={(e) => handleUpdateField(activeFormat.id, field.id, 'role', e.target.value as FieldRole)}
                      >
                        <option value="Condition">Condition (Match)</option>
                        <option value="rd">rd (Dest GPR)</option>
                        <option value="rs1">rs1 (Src1 GPR)</option>
                        <option value="rs2">rs2 (Src2 GPR)</option>
                        <option value="imm">imm (Immediate)</option>
                        <option value="None">None</option>
                      </select>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* 2. Center: Instruction DB Table */}
      <div className="panel" style={{ display: 'flex', flexDirection: 'column', overflow: 'hidden', height: '100%' }}>
        <div className="panel-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h2 className="panel-title">Instruction Definitions Database</h2>
          <button className="btn btn-primary" style={{ padding: '4px 10px', fontSize: '11px' }} onClick={handleAddInstruction}>
            + Add Instruction
          </button>
        </div>

        <div style={{ flex: 1, overflowY: 'auto', padding: '12px' }}>
          <table className="instruction-table" style={{ width: '100%', borderCollapse: 'collapse', fontSize: '11px', color: '#ccc' }}>
            <thead>
              <tr style={{ borderBottom: '2px solid #222', textAlign: 'left', height: '30px' }}>
                <th style={{ padding: '6px' }}>Name</th>
                <th style={{ padding: '6px' }}>Format</th>
                <th style={{ padding: '6px', width: '220px' }}>Match Conditions</th>
                <th style={{ padding: '6px' }}>EX Mapping</th>
                <th style={{ padding: '6px', width: '60px' }}>uOp</th>
                <th style={{ padding: '6px' }}>Alloc</th>
                <th style={{ padding: '6px' }}>Flags</th>
                <th style={{ padding: '6px', textAlign: 'center' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {instructions.map((inst) => {
                const currentFmt = formats.find((f) => f.id === inst.formatId) || formats[0];
                const condFields = currentFmt?.fields.filter((fd) => fd.role === 'Condition') || [];

                return (
                  <tr key={inst.id} style={{ borderBottom: '1px solid #1a1a1a', height: '45px' }}>

                    {/* Name */}
                    <td style={{ padding: '4px' }}>
                      <input
                        type="text"
                        style={{ backgroundColor: '#111', border: '1px solid #222', color: '#fff', width: '90px', padding: '4px 6px', fontSize: '11px' }}
                        value={inst.name}
                        onChange={(e) => handleUpdateInstruction(inst.id, 'name', e.target.value.toUpperCase().replace(/\s+/g, ''))}
                      />
                    </td>

                    {/* Format Selector */}
                    <td style={{ padding: '4px' }}>
                      <select
                        style={{ backgroundColor: '#111', border: '1px solid #222', color: '#aaa', padding: '4px', fontSize: '11px', width: '80px' }}
                        value={inst.formatId}
                        onChange={(e) => {
                          const newFmtId = e.target.value;
                          const newFmt = formats.find((f) => f.id === newFmtId);
                          const freshConds: Record<string, string> = {};
                          newFmt?.fields.forEach((fd) => {
                            if (fd.role === 'Condition') {
                              freshConds[fd.name] = "7'b0000000";
                            }
                          });
                          onChangeInstructions(
                            instructions.map((it) =>
                              it.id === inst.id
                                ? { ...it, formatId: newFmtId, conditions: freshConds }
                                : it
                            )
                          );
                        }}
                      >
                        {formats.map((f) => (
                          <option key={f.id} value={f.id}>
                            {f.name}
                          </option>
                        ))}
                      </select>
                    </td>

                    {/* Conditions */}
                    <td style={{ padding: '4px' }}>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '3px' }}>
                        {condFields.length === 0 && <span style={{ color: '#666', fontSize: '9px' }}>No condition fields</span>}
                        {condFields.map((fd) => (
                          <div key={fd.id} style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                            <span style={{ fontSize: '9px', color: '#888', minWidth: '40px' }}>{fd.name}:</span>
                            <input
                              type="text"
                              placeholder="e.g. 7'b0110011"
                              style={{ backgroundColor: '#090909', border: '1px solid #222', color: '#00ff66', fontSize: '10px', padding: '2px 4px', width: '130px' }}
                              value={inst.conditions[fd.name] || ''}
                              onChange={(e) => handleUpdateInstructionCondition(inst.id, fd.name, e.target.value)}
                            />
                          </div>
                        ))}
                      </div>
                    </td>

                    {/* Target Core Path Mapping */}
                    <td style={{ padding: '4px' }}>
                      <select
                        style={{ backgroundColor: '#111', border: '1px solid #222', color: '#aaa', padding: '4px', fontSize: '11px', width: '90px' }}
                        value={inst.exPathId}
                        onChange={(e) => handleUpdateInstruction(inst.id, 'exPathId', e.target.value)}
                      >
                        {coresList.map((core) => (
                          <option key={core.id} value={core.id}>
                            {core.name}
                          </option>
                        ))}
                      </select>
                    </td>

                    {/* Micro-op */}
                    <td style={{ padding: '4px' }}>
                      <input
                        type="number"
                        min="0"
                        max="31"
                        style={{ backgroundColor: '#111', border: '1px solid #222', color: '#fff', width: '45px', padding: '4px', fontSize: '11px' }}
                        value={inst.microop}
                        onChange={(e) => handleUpdateInstruction(inst.id, 'microop', parseInt(e.target.value) || 0)}
                      />
                    </td>

                    {/* Destination allocation */}
                    <td style={{ padding: '4px', textAlign: 'center' }}>
                      <input
                        type="checkbox"
                        checked={inst.newregAlloc}
                        onChange={(e) => handleUpdateInstruction(inst.id, 'newregAlloc', e.target.checked)}
                      />
                    </td>

                    {/* Control Flags */}
                    <td style={{ padding: '4px' }}>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '2px', fontSize: '9px' }}>
                        <label style={{ display: 'flex', alignItems: 'center', gap: '3px' }}>
                          <input
                            type="checkbox"
                            checked={inst.jump}
                            onChange={(e) => handleUpdateInstruction(inst.id, 'jump', e.target.checked)}
                          />
                          Jump
                        </label>
                        <label style={{ display: 'flex', alignItems: 'center', gap: '3px' }}>
                          <input
                            type="checkbox"
                            checked={inst.jumpReg}
                            onChange={(e) => handleUpdateInstruction(inst.id, 'jumpReg', e.target.checked)}
                          />
                          JmpReg
                        </label>
                        <label style={{ display: 'flex', alignItems: 'center', gap: '3px' }}>
                          <input
                            type="checkbox"
                            checked={inst.branch}
                            onChange={(e) => handleUpdateInstruction(inst.id, 'branch', e.target.checked)}
                          />
                          Branch
                        </label>
                      </div>
                    </td>

                    {/* Remove Action */}
                    <td style={{ padding: '4px', textAlign: 'center' }}>
                      <button
                        className="btn"
                        style={{ padding: '2px 8px', borderColor: '#ff2d55', color: '#ff2d55', fontSize: '10px' }}
                        onClick={() => handleRemoveInstruction(inst.id)}
                      >
                        Remove
                      </button>
                    </td>

                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {/* 3. Right Panel: Code Preview and file Download */}
      <div className="panel code-panel" style={{ display: 'flex', flexDirection: 'column', overflow: 'hidden', height: '100%', width: '100%', minWidth: 0 }}>
        <div className="panel-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h2 className="panel-title">Generated Decoder SV</h2>
          <div className="button-group">
            <button className="btn" onClick={handleCopy}>
              {copied ? 'Copied!' : 'Copy Code'}
            </button>
            <button className="btn btn-primary" onClick={onDownloadProject} disabled={!downloadEnabled} title={downloadError || undefined}>
              Download Project
            </button>
          </div>
        </div>
        {downloadError && <div className="config-error">{downloadError}</div>}
        <div className="code-container" style={{ flex: 1, overflowY: 'auto' }}>
          <pre className="code-pre">
            {generatedCode}
          </pre>
        </div>
      </div>

    </main>
  );
};
