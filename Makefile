
# Path from current directory to top level ableC repository
ABLEC_BASE?=../ableC
# Path from current directory to top level extensions directory
EXTS_BASE?=../extensions

# The configuration currently being built
CONF?=rel
# The directory containing main files
DRIVER_DIR=drivers
# The top-level directory in which to place generated files
BIN_DIR=bin
# The directory in which to place configuration-specific generated files
TARGET_DIR=$(BIN_DIR)/$(CONF)
# Additional directories for make to find files
VPATH=$(DRIVER_DIR):$(TARGET_DIR)

# The name of the jar file to build
ABLEC_JAR_NAME=ableC.jar
# The jar file to build
ABLEC_JAR=$(BIN_DIR)/ableC.jar
# The artifact specification grammar to compile
ARTIFACT=artifact
# All directories containing grammars that may be included
GRAMMAR_DIRS=$(ABLEC_BASE)/grammars $(wildcard $(EXTS_BASE)/*/grammars)
# All silver files in included grammars, to be included as dependancies
GRAMMAR_SOURCES=$(shell find $(GRAMMAR_DIRS) -name *.sv -print0 | xargs -0)
# Flags passed to silver including the appropriate directories
override SVFLAGS+=$(addprefix -I ,$(GRAMMAR_DIRS))

# Extended C files to compile that should be included in all targets
COMMON_XC_FILES=$(wildcard *.xc)
# Extended C files to compile that are target-specific
DRIVER_XC_FILES=$(wildcard $(DRIVER_DIR)/*.xc)
# All extended C files to compile
XC_FILES=$(COMMON_XC_FILES) $(DRIVER_XC_FILES)
# C files to be generated that should be included in all targets
COMMON_GEN_C_FILES=$(addprefix $(TARGET_DIR)/,$(COMMON_XC_FILES:.xc=.c))
# C files to be generated that are target-specific
DRIVER_GEN_C_FILES=$(addprefix $(TARGET_DIR)/,$(DRIVER_XC_FILES:$(DRIVER_DIR)/%.xc=%.c))
# All C files to be generated
GEN_C_FILES=$(COMMON_GEN_C_FILES) $(DRIVER_GEN_C_FILES)
# C source files to be compiled that should be included in all targets
COMMON_C_FILES=$(wildcard *.c)
# C source files to be compiled that are target-specific
DRIVER_C_FILES=$(wildcard $(DRIVER_DIR)/*.c)
# All C source files to be compiled
C_FILES=$(COMMON_C_FILES) $(DRIVER_C_FILES)
# All object files that should be included in all targets
COMMON_OBJECTS=$(COMMON_GEN_C_FILES:.c=.o) $(addprefix $(TARGET_DIR)/,$(COMMON_C_FILES:.c=.o))
# All object files that should be included in all targets
DRIVER_OBJECTS=$(DRIVER_GEN_C_FILES:.c=.o) $(addprefix $(TARGET_DIR)/,$(DRIVER_C_FILES:$(DRIVER_DIR)/%.c=%.o))
# All object files that should be generated
OBJECTS=$(COMMON_OBJECTS) $(DRIVER_OBJECTS)
# All executables that should be generated
TARGETS=$(DRIVER_OBJECTS:.o=)

# All directories contining extension header files that may be included
INCLUDE_DIRS=. $(wildcard $(EXTS_BASE)/*/include)
# All header files that may be included, to be included as dependencies in XC files
XC_INCLUDE_SOURCES=$(foreach dir,$(INCLUDE_DIRS),$(wildcard $(dir)/*.*h) $(wildcard $(dir)/*.pl))
# All header files that may be included, to be included as dependencies in C files
C_INCLUDE_SOURCES=$(foreach dir,$(INCLUDE_DIRS),$(wildcard $(dir)/*.h))
# Flags passed to ableC including the appropriate directories
override CPPFLAGS+=$(addprefix -I,$(INCLUDE_DIRS))
# Flags passed to Java when invoking ableC
override JAVAFLAGS+=-Xss1G -Xmx15G

# Flags passed to the C compiler, e.g. to enable various compiler extensions
override CFLAGS+=-fopenmp

# All directories contining extension libraries that may be linked
LIB_DIRS=$(wildcard $(EXTS_BASE)/*/lib)
# Flags passed to the linker specifying the appropriate directories
override LDFLAGS+=$(addprefix -L,$(LIB_DIRS))
# Flags passed to the linker specifying libraries to link
# Specify libsearch is to be linked statically, everything else dynamically
LDLIBS=-lpthread -lgc -lm -lgomp

# All directories contining extension library sources
SRC_DIRS=$(wildcard $(EXTS_BASE)/*/src)
# All extension library targets
LIBS=$(SRC_DIRS:src=libs)
# All C and XC files used to build libraries, to be included as dependencies
SRC_SOURCES=$(foreach dir,$(SRC_DIRS),$(wildcard $(dir)/*.*c))

override CPPFLAGS+=-DMG_ENABLE_SSI

ifeq ($(CONF), rel)
  override CPPFLAGS+=-DNDEBUG
  override CFLAGS+=-O3
  override LDFLAGS+=-O3
else ifeq ($(CONF), ssl)
  override CPPFLAGS+=-DNDEBUG -DSSL -DMG_ENABLE_MBEDTLS
  override CFLAGS+=-O3
  override LDFLAGS+=-O3
  override LDLIBS+=-lmbedtls -lmbedx509 -lmbedcrypto
else ifeq ($(CONF), dbg)
  override CPPFLAGS+=-DDEBUG
  override CFLAGS+=-O0 -g
  override LDFLAGS+=-O0
else ifeq ($(CONF), dbg_ssl)
  override CPPFLAGS+=-DDEBUG -DSSL -DMG_ENABLE_MBEDTLS
  override CFLAGS+=-O0 -g
  override LDFLAGS+=-O0
  override LDLIBS+=-lmbedtls -lmbedx509 -lmbedcrypto
else
  $(error Invalid build configuration $(CONF))
endif

all: $(ABLEC_JAR) $(GEN_C_FILES) $(OBJECTS) $(TARGETS)

libs: $(LIBS)

$(LIBS):
	$(MAKE) -C $(@:libs=src)

$(ABLEC_JAR): $(GRAMMAR_SOURCES) | $(BIN_DIR)
	touch $(wildcard $(ARTIFACT)/*.sv)
	silver-ableC -o $@ $(SVFLAGS) $(ARTIFACT)

$(TARGET_DIR)/%.c: %.xc $(XC_INCLUDE_SOURCES) $(ABLEC_JAR) | $(TARGET_DIR)
	java $(JAVAFLAGS) -jar $(ABLEC_JAR) $< $(CPPFLAGS) $(XCFLAGS)
	mv $(<:.xc=.i) $(dir $@)
	mv $(<:.xc=.c) $@

$(TARGET_DIR)/%.o: %.c $(C_INCLUDE_SOURCES) | $(TARGET_DIR)
	$(CC) -c $(CPPFLAGS) $(CFLAGS) $< -o $@

$(TARGET_DIR)/%: $(TARGET_DIR)/%.o $(COMMON_OBJECTS) $(SRC_SOURCES) | libs
	$(CC) $(LDFLAGS) $< $(COMMON_OBJECTS) $(LOADLIBES) $(LDLIBS) -o $@

$(BIN_DIR) $(TARGET_DIR):
	mkdir -p $@

# Remove everything but C files and ableC jar
mostlyclean:
	rm -rf $(OBJECTS) $(TARGETS) *.i *~ *.copperdump.html build.xml

# Remove everything but the ableC jar
clean: mostlyclean
	rm -rf $(GEN_C_FILES)

# Remove everything
realclean: clean
	rm -rf $(BIN_DIR)

.PHONY: rel dbg all libs $(LIBS) mostlyclean clean realclean
