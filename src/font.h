#ifndef FONT_H
#define FONT_H

typedef unsigned char u8;
typedef char i8;

typedef unsigned short u16;
typedef short i16;

typedef unsigned int u32;
typedef int i32;


typedef struct {
	u32	scaler_type;
	u16	numTables;
	u16	searchRange;
	u16	entrySelector;
	u16	rangeShift;
} offset_subtable;


typedef struct {
	u16 platformID;
	u16 platformSpecificID;
	u32 offset;
} cmap_encoding_subtable;


typedef struct {
	u16 version;
	u16 numberSubtables;
	cmap_encoding_subtable* subtables;
} cmap;

typedef struct {
	u16  format;
 	u16  length;
 	u16  language;
 	u16  segCountX2;
 	u16  searchRange;
 	u16  entrySelector;
 	u16  rangeShift;
	u16  reservedPad;
	u16  *endCode;
	u16  *startCode;
	u16  *idDelta;
	u16  *idRangeOffset;
	u16  *glyphIdArray;
} format4;

typedef struct {
	union { 
		char tag_c[4];
		u32	tag;
	};
	u32	checkSum;
	u32	offset;
	u32	length;
} table_directory;

typedef struct  {
	offset_subtable off_sub;
	table_directory* tbl_dir;
	format4* f4;
	cmap* cmap;
	char* glyf;
	char* loca;
	char* head;
} font_directory; 


typedef struct {
    u8 on_curve: 1;
    u8 x_short: 1;
    u8 y_short: 1;
    u8 repeat: 1;
    u8 x_short_pos: 1;
    u8 y_short_pos: 1;
    u8 reserved1: 1;
    u8 reserved2: 1;
} glyph_flag_bits;


typedef union {
    glyph_flag_bits bits;
    u8 flag;
} glyph_flag;


typedef struct {
	u16 numberOfContours;
	i16 xMin;
	i16 yMin;
	i16 xMax;
	i16 yMax;
	u16 instructionLength;
	u8* instructions;
	glyph_flag* flags;
	i16* xCoordinates;
	i16* yCoordinates;
	u16* endPtsOfContours;
} glyph_outline;

char* read_file(char *file_name, int* file_size);
void read_font_directory(char* file_start, char** mem, font_directory* ft);
glyph_outline get_glyph_outline(font_directory* ft, u32 glyph_index);
int get_glyph_index(font_directory* ft, u16 code_point);
void print_glyph_outline(glyph_outline *outline);

#endif // FONT_H