#
#                     OpenBIOS - free your system!
#                             ( Utilities )
#
#  This program is part of a free implementation of the IEEE 1275-1994
#  Standard for Boot (Initialization Configuration) Firmware.
#
#  Copyright (C) 2001-2006 Stefan Reinauer
#  Copyright (C) 2006-2009 coresystems GmbH
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; version 2 of the License.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA, 02110-1301 USA
#

PROGRAM := toke

DESTDIR ?= /usr/local

# toke is a build-host utility.  Keep its compiler separate from any target
# compiler inherited by a firmware or cross-toolchain build, while preserving
# compatibility with callers that explicitly pass CC=...
ifeq ($(origin HOSTCC), undefined)
ifeq ($(origin CC), default)
HOSTCC := cc
else
HOSTCC := $(CC)
endif
endif

ifeq ($(origin HOSTSTRIP), undefined)
ifeq ($(origin STRIP), undefined)
HOSTSTRIP := strip
else
HOSTSTRIP := $(STRIP)
endif
endif

CPPFLAGS ?=
CPPFLAGS += -I../shared
CFLAGS ?= -O2 -Wall -Werror -Wno-pointer-sign
LDFLAGS ?=
LDLIBS ?=

HOSTCPPFLAGS ?= $(CPPFLAGS)
HOSTCFLAGS ?= $(CFLAGS)
HOSTLDFLAGS ?= $(LDFLAGS)
HOSTLDLIBS ?= $(LDLIBS)

LOCAL_OBJS := clflags.o conditl.o devnode.o dictionary.o emit.o errhandler.o \
	flowcontrol.o macros.o nextfcode.o parselocals.o scanner.o stack.o \
	stream.o strsubvocab.o ticvocab.o toke.o tokzesc.o tracesyms.o \
	usersymbols.o
SHARED_OBJS := classcodes.o
OBJS := $(LOCAL_OBJS) $(SHARED_OBJS)
DEPS := $(OBJS:.o=.d)

.PHONY: all clean documentation install strip
.DELETE_ON_ERROR:

all: $(PROGRAM)

$(PROGRAM): $(OBJS)
	$(HOSTCC) $(HOSTLDFLAGS) -o $@ $(OBJS) $(HOSTLDLIBS)

%.o: %.c
	$(HOSTCC) $(HOSTCPPFLAGS) $(HOSTCFLAGS) -MMD -MP \
		-MT $@ -MF $(@:.o=.d) -c -o $@ $<

classcodes.o: ../shared/classcodes.c
	$(HOSTCC) $(HOSTCPPFLAGS) $(HOSTCFLAGS) -MMD -MP \
		-MT $@ -MF $(@:.o=.d) -c -o $@ $<

# Stripping is explicit so normal and debug builds retain their symbols, and a
# strip failure cannot leave a linked program that Make later treats as valid.
strip: $(PROGRAM)
	$(HOSTSTRIP) $(PROGRAM)

clean:
	rm -f $(OBJS) $(DEPS) *~
	rm -f $(PROGRAM)

documentation: *.c *.h toke.doxygen
	@doxygen toke.doxygen

install: $(PROGRAM)
	mkdir -p $(DESTDIR)/bin
	cp $(PROGRAM) $(DESTDIR)/bin/$(PROGRAM)

-include $(DEPS)
