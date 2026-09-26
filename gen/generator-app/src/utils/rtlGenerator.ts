import schedulerSource from '../../../src/RTL/eulsukdo_scheduler.sv?raw';
import nelSource from '../../../src/RTL/new_entry_logic.sv?raw';
import nelAgentSource from '../../../src/RTL/new_entry_logic_agent.sv?raw';
import prmSource from '../../../src/RTL/physical_register_mapper.sv?raw';
import istSource from '../../../src/RTL/instruction_state_table.sv?raw';
import rsSource from '../../../src/RTL/ready_station.sv?raw';
import wbcSource from '../../../src/RTL/write_back_concatenation.sv?raw';
import fclSource from '../../../src/RTL/flow_control_logic.sv?raw';
import elementsSource from '../../../src/RTL/_element_logics.sv?raw';
import flowDetectSource from '../../../src/RTL/flow_detect_unit.sv?raw';

export interface CoreTypeConfig {
  id: string;
  name: string;
  count: number;
  stroke: string;
}

export interface SchedulerConfig {
  decodeWidth: number;
  phyRegs: number;
  robEntries: number;
  coresList: CoreTypeConfig[];
  prmUpdate: number;
  prmBuffer: number;
  unallocatePhyreg: number;
  flowWindows: number;
  isaName?: string;
  instBitWidth?: number;
  instRegs?: number;
  instOperands?: number;
  instImm?: number;
  microopBitWidth?: number;
}

export const rtlSources: Record<string, string> = {
  'eulsukdo_scheduler.sv': schedulerSource,
  'new_entry_logic.sv': nelSource,
  'new_entry_logic_agent.sv': nelAgentSource,
  'physical_register_mapper.sv': prmSource,
  'instruction_state_table.sv': istSource,
  'ready_station.sv': rsSource,
  'write_back_concatenation.sv': wbcSource,
  'flow_control_logic.sv': fclSource,
  'flow_detect_unit.sv': flowDetectSource,
  '_element_logics.sv': elementsSource,
};

export function validateSchedulerConfig(config: SchedulerConfig): string | null {
  const positive = [config.decodeWidth, config.phyRegs, config.robEntries, config.prmUpdate,
    config.prmBuffer, config.unallocatePhyreg, config.flowWindows, config.instBitWidth ?? 32,
    config.instRegs ?? 32, config.instImm ?? 32, config.microopBitWidth ?? 5];
  if (positive.some(value => !Number.isSafeInteger(value) || value < 1)) return '모든 구조 및 ISA 파라미터는 1 이상의 정수여야 합니다.';
  if (config.phyRegs < (config.instRegs ?? 32)) return '물리 레지스터 수는 ISA 레지스터 수 이상이어야 합니다.';
  if (config.robEntries < config.decodeWidth || config.phyRegs < config.decodeWidth)
    return 'IST와 물리 레지스터 수는 디코드 폭 이상이어야 합니다.';
  if (config.flowWindows < 2 || config.robEntries < 2) return 'Flow window와 IST는 각각 2개 이상이어야 합니다.';
  if (config.instOperands !== undefined && config.instOperands !== 2)
    return '현재 디코더 생성은 소스 오퍼랜드 2개를 지원합니다.';
  if (!config.coresList || config.coresList.length < 2 || config.coresList.some(core => !Number.isSafeInteger(core.count) || core.count < 1))
    return '실행 경로를 2종류 이상 만들고 각 경로에 코어를 1개 이상 배치하세요.';
  if (!/^[a-zA-Z_][a-zA-Z_0-9]*$/.test(config.isaName ?? 'eulsukdo'))
    return 'ISA 이름은 SystemVerilog 식별자로 작성하세요.';
  return null;
}

// Mirror the public port and localparam declarations from the actual gen scheduler.
// Only decoder inputs become internal wires; execution units and IM stay external.
export function generateRTL(config: SchedulerConfig): string {
  const error = validateSchedulerConfig(config);
  if (error) throw new Error(error);

  const totalCores = config.coresList.reduce((sum, core) => sum + core.count, 0);
  const defaults: Record<string, string> = {
    IS_INST_BITWIDTH: String(config.instBitWidth ?? 32),
    IS_INST_REGS: String(config.instRegs ?? 32),
    IS_INST_OPERANDS: String(config.instOperands ?? 2),
    IS_INST_IMM: String(config.instImm ?? 32),
    EX_INST_MICROOP_BITWIDTH: String(config.microopBitWidth ?? 5),
    STRUCT_DECODE_NEW_INST: String(config.decodeWidth),
    STRUCT_INST_STATE_ENTRIES: String(config.robEntries),
    STRUCT_PHYREGS: String(config.phyRegs),
    STRUCT_EX_PATH: String(config.coresList.length),
    STRUCT_RS_OUT_ENTRY: `{${config.coresList.map(core => core.count).join(', ')}}`,
    STRUCT_EX_CORES: String(totalCores),
    STRUCT_EX_OUT_RESULT: `{${Array(totalCores).fill(1).join(', ')}}`,
    STRUCT_EX_OUT_RESULT_SUM: String(totalCores),
    STRUCT_EX_BRANCH: '1',
    STRUCT_PRM_ENTRY_UPDATE: String(config.prmUpdate),
    STRUCT_PRM_ENTRY_BUFFER: String(config.prmBuffer),
    STRUCT_UNALLOCATE_PHYREG: String(config.unallocatePhyreg),
    STRUCT_FLOW_WINDOWS: String(config.flowWindows),
  };
  const headerEnd = schedulerSource.indexOf('\n);');
  if (headerEnd < 0) throw new Error('Scheduler module header not found');
  let header = schedulerSource.slice(0, headerEnd + 3)
    .replace('module eulsukdo_scheduler #(', 'module eulsukdo_example_top #(');
  for (const [name, value] of Object.entries(defaults)) {
    const pattern = new RegExp(`^(\\s*parameter int ${name}(?:\\[[^\\]]+\\])?\\s*=\\s*)[^\\n]*?(?=,\\s*$)`, 'm');
    if (!pattern.test(header)) throw new Error(`Scheduler parameter not found: ${name}`);
    header = header.replace(pattern, (_, prefix: string) => `${prefix}${value}`);
  }
  const decoderLines = header.split('\n').filter(line => /^\s*input\s+wire\s+.*i_nel_decode_\w+,?\s*$/.test(line));
  if (decoderLines.length !== 10) throw new Error('Scheduler decoder port list changed');
  header = header.split('\n').filter(line => !decoderLines.includes(line)).join('\n');
  const internalWires = decoderLines.map(line => line.replace('input  wire', 'wire       ').replace(/,\s*$/, ';')).join('\n');
  const portNames = [...header.matchAll(/^\s*(?:input|output)\s+wire\s+(?:\[[^\]]+\]\s+)?(\w+),?\s*$/gm)].map(match => match[1]);
  const ports = portNames.map(name => `        .${name.padEnd(30)}(${name})`).join(',\n');
  const decoderPorts: Record<string, string> = {
    rd_o: 'rd', rs_o: 'rs', exception_o: 'exception', newreg_alloc_o: 'newreg',
    jump_o: 'jump', jump_reg_o: 'jump_reg', branch_o: 'branch',
    expath_o: 'expath', microop_o: 'microop', imm_o: 'imm',
  };
  const widths: Record<string, string> = {
    rd_o: '_BITWIDTH_IS_INST_REGS', rs_o: '(IS_INST_OPERANDS*_BITWIDTH_IS_INST_REGS)',
    expath_o: '_BITWIDTH_STRUCT_EX_PATH', microop_o: 'EX_INST_MICROOP_BITWIDTH', imm_o: 'IS_INST_IMM',
  };
  const decoderConnections = Object.entries(decoderPorts).map(([out, name]) => {
    const width = widths[out];
    const slice = width ? `[d_idx*${width} +: ${width}]` : '[d_idx]';
    return `            .${out.padEnd(18)}(i_nel_decode_${name}${slice})`;
  }).join(',\n');

  return `${header}\n\n    // gen scheduler input bundles are driven by the generated ISA decoder.\n${internalWires}\n\n    genvar d_idx;\n    generate\n        for (d_idx = 0; d_idx < STRUCT_DECODE_NEW_INST; d_idx = d_idx + 1) begin : GEN_DECODER\n            ${config.isaName ?? 'eulsukdo'}_decoder #(\n                .IS_INST_BITWIDTH(IS_INST_BITWIDTH),\n                .IS_INST_REGS(IS_INST_REGS),\n                .IS_INST_OPERANDS(IS_INST_OPERANDS),\n                .IS_INST_IMM(IS_INST_IMM),\n                .EX_INST_MICROOP_BITWIDTH(EX_INST_MICROOP_BITWIDTH),\n                .STRUCT_EX_PATH(STRUCT_EX_PATH)\n            ) U_DECODER (\n                .inst_i(i_im_recv_inst[d_idx*IS_INST_BITWIDTH +: IS_INST_BITWIDTH]),\n${decoderConnections}\n            );\n        end\n    endgenerate\n\n    eulsukdo_scheduler #(\n${Object.keys(defaults).map(name => `        .${name}(${name})`).join(',\n')},\n        .IS_INST_PC_BITWIDTH(IS_INST_PC_BITWIDTH),\n        .IS_INST_PC_STEP(IS_INST_PC_STEP),\n        .STRUCT_FLOW_PC_MAX_RANGE(STRUCT_FLOW_PC_MAX_RANGE)\n    ) U_SCHEDULER_CORE (\n${ports},\n${decoderLines.map(line => {
    const name = line.match(/(i_nel_decode_\w+)/)?.[1];
    return `        .${name?.padEnd(30)}(${name})`;
  }).join(',\n')}\n    );\n\n    // == EX Area START ==\n    // -- EX Instances --\n    // ==   EX Area END   ==\nendmodule\n`;
}
