#!/usr/bin/env python3
"""Build the 4 decode / 5 issue RV32I example importable by Core CAD."""

import json
from pathlib import Path


def field(name, msb, lsb, role):
    return {"id": f"f-{name}-{msb}-{lsb}", "name": name, "msb": msb, "lsb": lsb, "role": role}


def fmt(key, fields, parts=(), sign_extend=False):
    result = {"id": f"fmt-{key}", "name": f"{key}_type", "fields": fields}
    if parts:
        result["immediateParts"] = [
            {"id": f"imm-{key}-{index}", "sourceMsb": msb,
             "sourceLsb": lsb, "targetLsb": target}
            for index, (msb, lsb, target) in enumerate(parts)
        ]
        result["signExtendImmediate"] = sign_extend
    return result


opcode = field("opcode", 6, 0, "Condition")
rd = field("rd", 11, 7, "rd")
funct3 = field("funct3", 14, 12, "Condition")
rs1 = field("rs1", 19, 15, "rs1")
rs2 = field("rs2", 24, 20, "rs2")
funct7 = field("funct7", 31, 25, "Condition")
formats = [
    fmt("R", [opcode, rd, funct3, rs1, rs2, funct7]),
    fmt("I", [opcode, rd, funct3, rs1, field("imm", 31, 20, "imm")]),
    fmt("ISH", [opcode, rd, funct3, rs1, field("shamt", 24, 20, "None"), funct7],
        [(24, 20, 0)]),
    fmt("S", [opcode, field("imm4_0", 11, 7, "None"), funct3, rs1, rs2,
              field("imm11_5", 31, 25, "None")],
        [(31, 25, 5), (11, 7, 0)], True),
    fmt("B", [opcode, field("imm11", 7, 7, "None"), field("imm4_1", 11, 8, "None"),
              funct3, rs1, rs2, field("imm10_5", 30, 25, "None"), field("imm12", 31, 31, "None")],
        [(31, 31, 12), (7, 7, 11), (30, 25, 5), (11, 8, 1)], True),
    fmt("U", [opcode, rd, field("imm31_12", 31, 12, "None")],
        [(31, 12, 12)]),
    fmt("J", [opcode, rd, field("imm19_12", 19, 12, "None"), field("imm11", 20, 20, "None"),
              field("imm10_1", 30, 21, "None"), field("imm20", 31, 31, "None")],
        [(31, 31, 20), (19, 12, 12), (20, 20, 11), (30, 21, 1)], True),
    fmt("FENCE", [opcode, field("rd_zero", 11, 7, "Condition"), funct3,
                  field("rs1_zero", 19, 15, "Condition"), field("fm_pred_succ", 31, 20, "None")]),
]

instructions = []


def add(name, format_key, path, uop, opcode_bits, funct3_bits=None, funct7_bits=None,
        alloc=False, jump=False, jump_reg=False, branch=False, **extra):
    conditions = {"opcode": f"7'b{opcode_bits}"}
    if funct3_bits is not None:
        conditions["funct3"] = f"3'b{funct3_bits}"
    if funct7_bits is not None:
        conditions["funct7"] = f"7'b{funct7_bits}"
    conditions.update(extra)
    instructions.append({
        "id": f"inst-{name.lower()}", "name": name, "formatId": f"fmt-{format_key}",
        "conditions": conditions, "exPathId": str(path), "microop": uop,
        "newregAlloc": alloc, "jump": jump, "jumpReg": jump_reg, "branch": branch,
    })


for uop, (name, f3, f7) in enumerate([
    ("ADD", "000", "0000000"), ("SUB", "000", "0100000"),
    ("SLL", "001", "0000000"), ("SLT", "010", "0000000"),
    ("SLTU", "011", "0000000"), ("XOR", "100", "0000000"),
    ("SRL", "101", "0000000"), ("SRA", "101", "0100000"),
    ("OR", "110", "0000000"), ("AND", "111", "0000000"),
]):
    add(name, "R", 2, uop, "0110011", f3, f7, alloc=True)

for uop, (name, f3) in enumerate([
    ("ADDI", "000"), ("SLLI", "001"), ("SLTI", "010"),
    ("SLTIU", "011"), ("XORI", "100"), ("SRLI", "101"),
    ("SRAI", "101"), ("ORI", "110"), ("ANDI", "111"),
], start=10):
    shift = name in ("SLLI", "SRLI", "SRAI")
    add(name, "ISH" if shift else "I", 2, uop, "0010011", f3,
        "0100000" if name == "SRAI" else "0000000" if shift else None, alloc=True)

add("LUI", "U", 2, 19, "0110111", alloc=True)
add("AUIPC", "U", 2, 20, "0010111", alloc=True)

for uop, (name, f3) in enumerate([
    ("BEQ", "000"), ("BNE", "001"), ("BLT", "100"),
    ("BGE", "101"), ("BLTU", "110"), ("BGEU", "111"),
]):
    add(name, "B", 1, uop, "1100011", f3, branch=True)
add("JAL", "J", 1, 6, "1101111", alloc=True, jump=True)
add("JALR", "I", 1, 7, "1100111", "000", alloc=True, jump_reg=True)

for uop, (name, f3) in enumerate([
    ("LB", "000"), ("LH", "001"), ("LW", "010"),
    ("LBU", "100"), ("LHU", "101"),
]):
    add(name, "I", 3, uop, "0000011", f3, alloc=True)
for uop, (name, f3) in enumerate([("SB", "000"), ("SH", "001"), ("SW", "010")], start=5):
    add(name, "S", 3, uop, "0100011", f3)

add("FENCE", "FENCE", 1, 8, "0001111", "000", branch=True,
    rd_zero="5'b00000", rs1_zero="5'b00000")

config = {
    "projectName": "eulsukdo-rv32i-4d5iss",
    "scheduler": {
        "decodeWidth": 4, "phyRegs": 64, "robEntries": 128,
        "coresList": [
            {"id": "1", "name": "Branch", "count": 1, "stroke": "#ff5500"},
            {"id": "2", "name": "ALU", "count": 3, "stroke": "#00ccff"},
            {"id": "3", "name": "Memory", "count": 1, "stroke": "#ffcc00"},
        ],
        "prmUpdate": 3, "prmBuffer": 4, "unallocatePhyreg": 4, "flowWindows": 8,
    },
    "decoder": {
        "instBitWidth": 32, "instRegs": 32, "instOperands": 2,
        "instImm": 32, "microopBitWidth": 5, "isaName": "rv32i",
    },
    "formats": formats,
    "instructions": instructions,
}

assert len(instructions) == 38
output = Path(__file__).with_name("rv32i_4decode_5issue.json")
output.write_text(json.dumps(config, indent=2) + "\n")
print(output)
