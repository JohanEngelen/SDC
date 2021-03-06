module d.gc.bin;

enum InvalidBinID = 0xff;

struct Bin {
	import d.gc.run;
	RunDesc* current;
	
	import d.gc.rbtree;
	RBTree!(RunDesc, addrRunCmp) runTree;
}

struct BinInfo {
	ushort size;
	ubyte needPages;
	ushort slots;
	
	this(ushort size, ubyte needPages, ushort slots) {
		this.size = size;
		this.needPages = needPages;
		this.slots = slots;
	}
}

import d.gc.sizeclass;
immutable BinInfo[ClassCount.Small] binInfos = getBinInfos();
