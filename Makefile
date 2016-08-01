
SUBDIRS =  hello_world

all: subdirs
	@echo momodadadadada
subdirs:
	for n in $(SUBDIRS); do $(MAKE) -C $$n || exit 1; done

clean:
	for n in $(SUBDIRS); do $(MAKE) -C $$n clean; done

momoda: all