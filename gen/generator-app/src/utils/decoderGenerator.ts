import { type CoreTypeConfig } from './rtlGenerator';

export interface DecoderParamConfig {
  instBitWidth: number;
  instRegs: number;
  instOperands: number;
  instImm: number;
  microopBitWidth: number;
  isaName: string;
}

export type FieldRole = 'Condition' | 'rd' | 'rs1' | 'rs2' | 'imm' | 'None';

export interface FormatField {
  id: string;
  name: string;
  msb: number;
  lsb: number;
  role: FieldRole;
}

export interface ImmediatePart {
  id: string;
  sourceMsb: number;
  sourceLsb: number;
  targetLsb: number;
}

export interface InstructionFormat {
  id: string;
  name: string;
  fields: FormatField[];
  immediateParts?: ImmediatePart[];
  signExtendImmediate?: boolean;
}

export function immediateExpression(fmt: InstructionFormat, instImm: number, instBitWidth: number): string | null {
  const parts = fmt.immediateParts;
  if (!parts?.length) return null;
  const ordered = [...parts].sort((a, b) => b.targetLsb - a.targetLsb);
  const signBit = ordered[0].sourceMsb;
  const chunks: string[] = [];
  let nextBit = instImm;

  for (const part of ordered) {
    const width = part.sourceMsb - part.sourceLsb + 1;
    const topBit = part.targetLsb + width - 1;
    if (!Number.isInteger(width) || !Number.isInteger(part.targetLsb) ||
        part.sourceLsb < 0 || part.sourceMsb >= instBitWidth ||
        width < 1 || part.targetLsb < 0 || topBit >= nextBit) {
      return null;
    }
    const gap = nextBit - topBit - 1;
    if (gap) {
      chunks.push(chunks.length === 0 && fmt.signExtendImmediate
        ? `{${gap}{inst_i[${signBit}]}}` : `${gap}'b0`);
    }
    chunks.push(part.sourceMsb === part.sourceLsb
      ? `inst_i[${part.sourceMsb}]` : `inst_i[${part.sourceMsb}:${part.sourceLsb}]`);
    nextBit = part.targetLsb;
  }
  if (nextBit) chunks.push(`${nextBit}'b0`);
  return `{${chunks.join(', ')}}`;
}

export interface InstructionConfig {
  id: string;
  name: string;
  formatId: string;
  conditions: Record<string, string>; // fieldName -> matchValue (e.g. "opcode" -> "7'b0110011")
  exPathId: string;                  // Target core ID from coresList
  microop: number;                   // Micro-op code integer
  newregAlloc: boolean;
  jump: boolean;
  jumpReg: boolean;
  branch: boolean;
}

export function generateDecoderRTL(
  decConfig: DecoderParamConfig,
  formats: InstructionFormat[],
  instructions: InstructionConfig[],
  coresList: CoreTypeConfig[]
): string {
  const {
    instBitWidth,
    instRegs,
    instOperands,
    instImm,
    microopBitWidth,
    isaName,
  } = decConfig;

  const logRegWidth = Math.max(1, Math.ceil(Math.log2(instRegs)));
  const exPaths = coresList.length;
  const expathWidth = Math.max(1, Math.ceil(Math.log2(exPaths)));

  // Generate Field Unpacking declarations
  let unpackingLogic = '';
  formats.forEach((fmt) => {
    unpackingLogic += `    // Unpacked fields for format: ${fmt.name}\n`;
    fmt.fields.forEach((field) => {
      const fieldWidth = field.msb - field.lsb + 1;
      if (fieldWidth > 0) {
        unpackingLogic += `    wire [${fieldWidth - 1}:0] fmt_${fmt.name}_${field.name} = inst_i[${field.msb}:${field.lsb}];\n`;
      }
    });
    unpackingLogic += '\n';
  });

  // Generate Instruction Decodes conditions
  let decodesLogic = '';
  instructions.forEach((inst, index) => {
    const fmt = formats.find((f) => f.id === inst.formatId);
    if (!fmt) return;

    // Build the matching conditions
    const condList: string[] = [];
    Object.entries(inst.conditions).forEach(([fieldName, val]) => {
      if (val && val.trim() !== '') {
        condList.push(`fmt_${fmt.name}_${fieldName} == ${val.trim()}`);
      }
    });

    const conditionStr = condList.length > 0 ? condList.join(' && ') : "1'b1";
    const coreIndex = coresList.findIndex((c) => c.id === inst.exPathId);
    const targetPathIdx = coreIndex >= 0 ? coreIndex : 0;
    const targetCoreName = coreIndex >= 0 ? coresList[coreIndex].name : 'UNKNOWN';

    // Register allocations
    const rdField = fmt.fields.find((f) => f.role === 'rd');
    const rs1Field = fmt.fields.find((f) => f.role === 'rs1');
    const rs2Field = fmt.fields.find((f) => f.role === 'rs2');
    const immField = fmt.fields.find((f) => f.role === 'imm');

    let rdAssign = 'rd_o = 0;';
    if (rdField) {
      rdAssign = `rd_o = fmt_${fmt.name}_${rdField.name};`;
    }

    // Register bundle rs_o
    let rsAssign = `rs_o = 0;`;
    if (rs1Field || rs2Field) {
      const rs2Val = rs2Field ? `fmt_${fmt.name}_${rs2Field.name}` : `${logRegWidth}'d0`;
      const rs1Val = rs1Field ? `fmt_${fmt.name}_${rs1Field.name}` : `${logRegWidth}'d0`;
      rsAssign = `rs_o = {${rs2Val}, ${rs1Val}};`;
    }

    // Immediate calculation with proper sign extension
    let immAssign = 'imm_o = 0;';
    const mappedImmediate = immediateExpression(fmt, instImm, instBitWidth);
    if (mappedImmediate) {
      immAssign = `imm_o = ${mappedImmediate};`;
    } else if (immField) {
      const fieldLen = immField.msb - immField.lsb + 1;
      if (fieldLen < instImm) {
        immAssign = `imm_o = {{${instImm - fieldLen}{fmt_${fmt.name}_${immField.name}[${fieldLen - 1}]}}, fmt_${fmt.name}_${immField.name}};`;
      } else {
        immAssign = `imm_o = fmt_${fmt.name}_${immField.name}[${instImm - 1}:0];`;
      }
    }

    const ifKeyword = index === 0 ? 'if' : 'else if';

    decodesLogic += `        ${ifKeyword} (${conditionStr}) begin : decode_${inst.name}\n`;
    decodesLogic += `            // Instruction: ${inst.name} (Format: ${fmt.name}, Core: ${targetCoreName})\n`;
    decodesLogic += `            ${rdAssign}\n`;
    decodesLogic += `            ${rsAssign}\n`;
    decodesLogic += `            ${immAssign}\n`;
    decodesLogic += `            exception_o    = 1'b0;\n`;
    decodesLogic += `            newreg_alloc_o = ${inst.newregAlloc ? "(rd_o != 0)" : "1'b0"};\n`;
    decodesLogic += `            jump_o         = ${inst.jump ? "1'b1" : "1'b0"};\n`;
    decodesLogic += `            jump_reg_o     = ${inst.jumpReg ? "1'b1" : "1'b0"};\n`;
    decodesLogic += `            branch_o       = ${inst.branch ? "1'b1" : "1'b0"};\n`;
    decodesLogic += `            expath_o       = ${expathWidth}'d${targetPathIdx};\n`;
    decodesLogic += `            microop_o      = ${microopBitWidth}'d${inst.microop};\n`;
    decodesLogic += `        end\n`;
  });

  if (instructions.length > 0) {
    decodesLogic += `        else begin : decode_default_illegal\n`;
    decodesLogic += `            exception_o = 1'b1;\n`;
    decodesLogic += `        end\n`;
  } else {
    decodesLogic += `        begin : decode_empty_default\n`;
    decodesLogic += `            exception_o = 1'b1;\n`;
    decodesLogic += `        end\n`;
  }

  return `\`timescale 1ns / 1ps

// =============================================================================
// 💡 Auto-Generated EULSUKDO Custom Instruction Decoder
//    - Instruction Width  : ${instBitWidth} bits
//    - Logic GPR Registers: ${instRegs}
//    - Max Operands / GPR : ${instOperands}
//    - Supported Core Paths: ${exPaths} (${coresList.map(c => c.name).join(', ')})
// =============================================================================

module ${isaName || 'eulsukdo'}_decoder #(
    parameter int IS_INST_BITWIDTH         = ${instBitWidth},
    parameter int IS_INST_REGS             = ${instRegs},
    parameter int IS_INST_OPERANDS         = ${instOperands},
    parameter int IS_INST_IMM              = ${instImm},
    parameter int EX_INST_MICROOP_BITWIDTH = ${microopBitWidth},
    parameter int STRUCT_EX_PATH           = ${exPaths},

    localparam int LOGICAL_REG_IDX_WIDTH   = $clog2(IS_INST_REGS),
    localparam int EX_PATH_IDX_WIDTH       = $clog2(STRUCT_EX_PATH)
) (
    input  wire [IS_INST_BITWIDTH-1:0]                      inst_i,

    // Register Index Decodes
    output reg  [LOGICAL_REG_IDX_WIDTH-1:0]                 rd_o,
    output reg  [(IS_INST_OPERANDS*LOGICAL_REG_IDX_WIDTH)-1:0] rs_o,

    // Control Flags
    output reg                                              exception_o,
    output reg                                              newreg_alloc_o,
    output reg                                              jump_o,
    output reg                                              jump_reg_o,
    output reg                                              branch_o,

    // Execution Mapping
    output reg  [EX_PATH_IDX_WIDTH-1:0]                      expath_o,
    output reg  [EX_INST_MICROOP_BITWIDTH-1:0]              microop_o,
    output reg  [IS_INST_IMM-1:0]                           imm_o
);

${unpackingLogic}
    // -------------------------------------------------------------------------
    // Decoding Combinational Logic
    // -------------------------------------------------------------------------
    always_comb begin
        // Default Assignments to prevent latch inference
        rd_o           = 0;
        rs_o           = 0;
        imm_o          = 0;
        exception_o    = 1'b1;
        newreg_alloc_o = 1'b0;
        jump_o         = 1'b0;
        jump_reg_o     = 1'b0;
        branch_o       = 1'b0;
        expath_o       = 0;
        microop_o      = 0;

${decodesLogic}    end

endmodule
`;
}
