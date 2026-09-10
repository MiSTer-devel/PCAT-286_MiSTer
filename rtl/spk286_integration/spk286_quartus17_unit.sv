// Quartus Prime 17.0 compatibility compilation unit.
//
// The pinned source remains byte-identical under vendor/spk286. Quartus 17
// otherwise warns that two package-qualified constants used inside expression
// operands are implicit nets. Importing the generated package at compilation-
// unit scope lets this older parser bind those names without changing SPK286.
import spk286_microcode_pkg::*;
`include "vendor/spk286/rtl/spk286.sv"
