# Copyright 2022 ETH Zurich
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0
# Author: Robert Balas (balasr@iis.ee.ethz.ch)

# Compile options (passed to make) e.g. make NDEBUG=yes
# NDEBUG    Make release build
# CONFIG_USE_NEWLIB Link against libc
# CONFIG_CC_LTO       Enable link time optimization
# CONFIG_CC_SANITIZE  Enable gcc sanitizer for debugging memory access problems
# CONFIG_CC_STACKDBG  Enable stack debugging information and warnings.
#           By default 1 KiB but can be changed with MAXSTACKSIZE=your_value

RISCV		?= $(HOME)/.riscv
RISCV_PREFIX	?= $(RISCV)/bin/riscv32-unknown-elf-
CC		= $(RISCV_PREFIX)gcc
OBJCOPY		= $(RISCV_PREFIX)objcopy
OBJDUMP		= $(RISCV_PREFIX)objdump
SIZE		= $(RISCV_PREFIX)size

# For out tree builds. We set a default for regular builds to make handling
# simpler
VPATH = .

# test if gcc is newer than version 8
GCC_GTEQ_8 = $(shell expr `$(CC) -dumpversion | cut -f1 -d.` \>= 8)

# User controllable standard makeflags
CFLAGS = -Os -g3
CPPFLAGS =
LDFLAGS =
LDLIBS =
ASFLAGS = -Os -g3

# Builtin mandatory flags. Need to be simply expanded variables for appends in
# sub-makefiles to work correctly
CV_CFLAGS := \
	-march=rv32imac -mabi=ilp32 -msmall-data-limit=8 -mno-save-restore \
	-fsigned-char -ffunction-sections -fdata-sections \
	-std=gnu11 \
	-Wall -Wextra -Wshadow -Wformat=2 -Wundef -Wconversion -Wno-unused-parameter

CV_ASFLAGS := \
	-march=rv32imac -mabi=ilp32 -msmall-data-limit=8 -mno-save-restore \
	-fsigned-char -ffunction-sections -fdata-sections \
	-x assembler-with-cpp

CV_CPPFLAGS :=

# note: linkerscript is included in target directory makefile.mk
CV_LDFLAGS := -nostartfiles -Wl,--gc-sections -Wl,-Map,memory.map # -Wl,--print-gc-sections

# check if we want a release build
ifeq ($(RELEASE),yes)
CV_CPPFLAGS += -DNDEBUG
endif

# do we need libc (by default yes)
ifeq ($(CONFIG_USE_NEWLIB),n)
$(warning Libc disabled. This setup is hard to get working and probably fails at the linker stage)
CV_LDFLAGS += -nolibc
else
# We want to link against newlib with where we provide our syscall
# implementation. Note we can't use --specs=nano.specs since that links against
# newlib and libgloss where the later provides already a syscall implementation
# (which is just forwarding the implementation with systemcalls). Actually we
# can use --specs=nano.specs and just provide your syscalls.c file. For the most
# part it works well; our implementation overwrites the one from libgloss, but
# when enabling LTO everything breaks apart because of duplicate symbols. So we
# do it the proper way: link everything by hand.

ifeq ($(GCC_GTEQ_8), 1)
# newer gcc
CV_LDFLAGS  += -nolibc -static
LDLIBS      += -lc_nano -lm_nano
else
# legacy link for older gcc (namely pulp-gcc)
CV_LDFLAGS  += -nostdlib -static
LDLIBS      += -lgcc -lc -lm -lgcc
endif

CV_CPPFLAGS    += -DCONFIG_USE_LIBC
endif

# stack debugging information
ifeq ($(CONFIG_CC_STACKDBG),y)
CV_CFLAGS += -fstack-usage
ifeq ($(CONFIG_CC_MAXSTACKSIZE),)
CV_CFLAGS += -Wstack-usage=1024
else
CV_CFLAGS += -Wstack-usage=$(CONFIG_CC_MAXSTACKSIZE)
endif
endif

# check if we want to debug with memory sanitiszers
ifeq ($(CONFIG_CC_SANITIZE),y)
CV_CFLAGS += -fsanitize=address -fsanitize=undefined -fsanitize=leak
endif

# link time optimization
# note that the gnu manpage recommends passing the optimization flags used at
# compile time also to the linker when using LTO (weird!) which is why we have
# CFLAGS in the linker target
ifeq ($(CONFIG_CC_LTO),y)
CV_CFLAGS += -flto
endif

# script paths
PLPSTIM   = scripts/pulpstim
PULPTRACE = scripts/pulptrace

# simulation names and paths
VSIM   = vsim
SIMDIR = sim
GVSIMDIR = gvsim
PULP_RISCV_GCC_TOOLCHAIN=$(RISCV) # for gvsoc

# force SRCS to be a "simply expanded variable"
SRCS :=
