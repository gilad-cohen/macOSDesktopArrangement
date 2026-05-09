APP := spaces-probe
SRC := Sources/spaces_probe.m
DRAG := drag-mouse
DRAG_SRC := Sources/drag_mouse.m

.PHONY: all clean run switch

all: $(APP) $(DRAG)

$(APP): $(SRC)
	clang -fobjc-arc -framework AppKit -framework CoreGraphics -framework Foundation -o $(APP) $(SRC)

$(DRAG): $(DRAG_SRC)
	clang -fobjc-arc -framework ApplicationServices -framework Foundation -o $(DRAG) $(DRAG_SRC)

run: $(APP)
	./$(APP)

switch: $(APP)
	./$(APP) --switch

clean:
	rm -f $(APP) $(DRAG)
