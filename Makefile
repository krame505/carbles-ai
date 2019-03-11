
# Path from current directory to top level ableC repository
ABLEC_BASE?=../ableC
# Path from current directory to top level extensions directory
EXTS_BASE?=../extensions

# The jar file to built
ABLEC_JAR=ableC.jar
# The artifact specification grammar to compile
ARTIFACT=artifact
# All directories containing grammars that may be included
GRAMMAR_DIRS=$(ABLEC_BASE)/grammars $(wildcard $(EXTS_BASE)/*/grammars)
# All silver files in included grammars, to be included as dependancies
GRAMMAR_SOURCES=$(shell find $(GRAMMAR_DIRS) -name *.sv -print0 | xargs -0)
# Flags passed to silver including the appropriate directories
override SVFLAGS+=$(addprefix -I ,$(GRAMMAR_DIRS))

# The directory in which to place intermediate files
BIN_DIR=bin

# All C files to compile
C_FILES=$(wildcard *.c)
# All extended C files to compile
XC_FILES=$(wildcard *.xc)
# All C files that should be generated
GEN_C_FILES=$(addprefix $(BIN_DIR)/,$(XC_FILES:.xc=.c))
# All object files that should be generated
OBJECTS=$(addprefix $(BIN_DIR)/,$(C_FILES:.c=.o) $(XC_FILES:.xc=.o))
# The executable that should be generated
TARGET=$(BIN_DIR)/run

# All directories contining extension header files that may be included
INCLUDE_DIRS=. $(wildcard $(EXTS_BASE)/*/include)
# All header files that may be included, to be included as dependencies
INCLUDE_SOURCES=$(foreach dir,$(INCLUDE_DIRS),$(wildcard $(dir)/*.*h))
# Flags passed to ableC including the appropriate directories
override CPPFLAGS+=$(addprefix -I,$(INCLUDE_DIRS))
# Flags passed to Java when invoking ableC
override JAVAFLAGS+=-Xss32M

# Flags passed to the C compiler, e.g. to enable various compiler extensions
override CFLAGS+=-lgc

# All directories contining extension libraries that may be linked
LIB_DIRS=$(wildcard $(EXTS_BASE)/*/lib)
# Flags passed to the linker specifying the appropriate directories
override LDFLAGS+=$(addprefix -L,$(LIB_DIRS))
# Flags passed to the linker specifying libraries to link
# Specify libsearch is to be linked statically, everything else dynamically
LDLIBS=-Wl,-Bstatic -lsearch -Wl,-Bdynamic -lpthread

# All directories contining extension library sources
SRC_DIRS=$(wildcard $(EXTS_BASE)/*/src)
# All extension library targets
LIBS=$(SRC_DIRS:src=libs)
# All C and XC files used to build libraries, to be included as dependencies
SRC_SOURCES=$(foreach dir,$(SRC_DIRS),$(wildcard $(dir)/*.*c))

rel: CFLAGS+=-O3 -DNDEBUG
rel: LDFLAGS+=-O3
rel: all

dbg: CFLAGS+=-O0 -g -DDEBUG
dbg: all

all: $(ABLEC_JAR) $(GEN_C_FILES) $(OBJECTS) $(TARGET)

libs: $(LIBS)

$(LIBS):
	$(MAKE) -C $(@:libs=src)

$(ABLEC_JAR): $(GRAMMAR_SOURCES)
	touch $(wildcard $(ARTIFACT)/*.sv)
	silver-ableC -o $@ $(SVFLAGS) $(ARTIFACT)

$(BIN_DIR)/%.c: %.xc $(INCLUDE_SOURCES) $(ABLEC_JAR) | $(BIN_DIR)
	java $(JAVAFLAGS) -jar $(ABLEC_JAR) $< $(CPPFLAGS) $(XCFLAGS)
	mv $*.i $@
	mv $*.c $@

$(BIN_DIR)/%.o: %.c $(INCLUDE_SOURCES) | $(BIN_DIR)
	$(CC) -c $(CPPFLAGS) $(CFLAGS) $< -o $@

$(TARGET): $(OBJECTS) $(SRC_SOURCES) | libs
	$(CC) $(LDFLAGS) $(OBJECTS) $(LOADLIBES) $(LDLIBS) -o $@

$(BIN_DIR):
	mkdir -p $@

clean:
	rm -rf *~ *.copperdump.html build.xml $(BIN_DIR)

realclean: clean
	rm -rf *.jar

.PHONY: rel dbg all libs $(LIBS) clean realclean
