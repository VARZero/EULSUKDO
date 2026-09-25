export interface VcdVariable {
  id: string;
  name: string;
  fullName: string;
  size: number;
  type: string;
}

export interface VcdCycle {
  cycle: number;
  timestamp: number;
  values: Record<string, string>;
}

export interface VcdData {
  timescale: string;
  vars: VcdVariable[];
  varsById: Record<string, VcdVariable>;
  timeline: number[];
  changes: Record<number, Record<string, string>>;
  cycles: VcdCycle[];
  clockVarId: string | null;
}

export function parseVcd(vcdText: string): VcdData {
  const vars: VcdVariable[] = [];
  const varsById: Record<string, VcdVariable> = {};
  const timeline: number[] = [];
  const changes: Record<number, Record<string, string>> = {};
  let pendingChanges: Record<string, string> = {};
  const cycles: VcdCycle[] = [];
  const scope: string[] = [];
  const values: Record<string, string> = {};
  let timescale = '1ns';
  let clockVarId: string | null = null;
  let definitions = true;
  let timestamp = 0;
  let hasTimestamp = false;
  let lastClockValue = 'x';

  const flush = () => {
    if (!hasTimestamp) return;
    timeline.push(timestamp);
    changes[timestamp] = pendingChanges;
    pendingChanges = {};
    const clockValue = clockVarId ? values[clockVarId] : undefined;
    if (clockVarId && lastClockValue === '0' && clockValue === '1') {
      cycles.push({ cycle: cycles.length, timestamp, values: { ...values } });
    }
    if (clockValue !== undefined) lastClockValue = clockValue;
  };

  const lines = vcdText.split(/\r?\n/);
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index].trim();
    if (!line) continue;
    if (definitions) {
      if (line.startsWith('$scope')) {
        const parts = line.split(/\s+/);
        if (parts[2]) scope.push(parts[2]);
      } else if (line.startsWith('$upscope')) {
        scope.pop();
      } else if (line.startsWith('$var')) {
        const parts = line.split(/\s+/);
        if (parts.length < 6) continue;
        const variable: VcdVariable = {
          type: parts[1], size: Number(parts[2]), id: parts[3],
          name: parts[4], fullName: [...scope, parts[4]].join('.'),
        };
        vars.push(variable);
        if (!varsById[variable.id]) varsById[variable.id] = variable;
        values[variable.id] = 'x';
        if (/^(clk|clock)$/i.test(variable.name) &&
          (!clockVarId || variable.fullName.split('.').length < varsById[clockVarId].fullName.split('.').length)) {
          clockVarId = variable.id;
        }
      } else if (line.startsWith('$timescale')) {
        const content = line.slice(10).replace('$end', '').trim();
        timescale = content || lines[++index]?.replace('$end', '').trim() || timescale;
      } else if (line.startsWith('$enddefinitions')) {
        definitions = false;
      }
      continue;
    }
    if (line[0] === '#') {
      const nextTime = Number(line.slice(1));
      if (!Number.isFinite(nextTime)) continue;
      if (hasTimestamp && nextTime !== timestamp) flush();
      timestamp = nextTime;
      hasTimestamp = true;
    } else if (/^[bBrR]/.test(line)) {
      const parts = line.split(/\s+/);
      if (parts[1] && varsById[parts[1]]) {
        values[parts[1]] = parts[0].slice(1).toLowerCase();
        pendingChanges[parts[1]] = values[parts[1]];
      }
    } else if (/^[01xXzZ]/.test(line)) {
      const id = line.slice(1);
      if (varsById[id]) {
        values[id] = line[0].toLowerCase();
        pendingChanges[id] = values[id];
      }
    }
  }
  if (!hasTimestamp) hasTimestamp = true;
  flush();
  if (!clockVarId || cycles.length === 0) {
    // A clockless VCD still gets a single state for inspection.
    cycles.push({ cycle: 0, timestamp, values: { ...values } });
  }
  return { timescale, vars, varsById, timeline, changes, cycles, clockVarId };
}

// Generate mock VCD data for demo and fallback
export function generateMockVcd(): string {
  return `$date
  Wed Jun 24 06:12:38 2026
$end
$version
  Eulsukdo Mock Sim
$end
$timescale
  10ns
$end
$scope module tb_eulsukdo_1dec3iss $end
$scope module U_EULSUKDO $end
$var reg 1 ! clk $end
$var reg 1 " reset_n $end
$var reg 32 # fcl_inst_pc [31:0] $end
$var reg 1 $ nel_block $end
$var reg 1 % ist_insert_available $end
$var reg 32 & reg_x2 [31:0] $end
$var reg 32 ' reg_x3 [31:0] $end
$var reg 32 ( reg_x4 [31:0] $end
$var reg 32 ) reg_x5 [31:0] $end
$var reg 32 * ex_alu_result [31:0] $end
$var reg 1 + done_alu $end
$var reg 1 , done_branch $end
$upscope $end
$upscope $end
$enddefinitions $end
#0
$dumpvars
0!
0"
bx #
0$
1%
b0 &
b0 '
b0 (
b0 )
bx *
0+
0,
$end
#10
1!
#20
0!
1"
#30
1!
b00000000000000000000000000000000 #
#40
0!
#50
1!
b00000000000000000000000000000100 #
b00000000000000000000000000001010 &
#60
0!
#70
1!
b00000000000000000000000000001000 #
b00000000000000000000000000000111 '
#80
0!
#90
1!
b00000000000000000000000000001100 #
b00000000000000000000000000000000 )
#100
0!
#110
1!
b00000000000000000000000000010000 #
#120
0!
#130
1!
b00000000000000000000000000000011 *
1+
#140
0!
#150
1!
b00000000000000000000000000000011 (
0+
#160
0!
#170
1!
b00000000000000000000000000001010 *
1+
#180
0!
#190
1!
b00000000000000000000000000001010 )
0+
#200
0!
#210
1!
1,
#220
0!
#230
1!
0,
#240
0!
`;
}
