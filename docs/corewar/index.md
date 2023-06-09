# Corewar Guide

Corewar is a coding game in which players write programs called
[warriors](warriors) to compete in a simulated memory known as the
[core](core).  Warriors battle to eliminate the opposition by causing them to
execute illegal instructions such as [DAT](../redcode/opcodes#dat_data).

Warriors are written in a programming language called [redcode](../redcode/) –
a language resembling assembly with each instruction occupying a single memory
address within the core.

A round takes place over a number of turns called cycles.  Each cycle, one
warrior executes a single instruction.  If a warrior is eliminated, the other
warrior wins the round.  If the maximum number of cycles is reached, the round
is a draw.

A match usually has multiple rounds with points awarded for wins and draws.  At
the end the warrior with the most points is the winner. Points will be rewarded
for overwriting an instruction of another warrior (hits) or if another warrior
process is terminated due to an [DAT](../redcode/opcodes#dat_data) instruction
that was written by this warrior (kill). 

