CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -O2

quill-inject: src/quill-inject.cpp
	$(CXX) $(CXXFLAGS) src/quill-inject.cpp -o quill-inject

install: quill-inject
	install -d $(DESTDIR)$(HOME)/.local/bin
	install -m 755 quill-inject $(DESTDIR)$(HOME)/.local/bin/quill-inject

clean:
	rm -f quill-inject

.PHONY: install clean
