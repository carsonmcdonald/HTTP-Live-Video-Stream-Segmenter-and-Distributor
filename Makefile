FFLIBS=`pkg-config --libs libavformat libavcodec libavutil`
FFFLAGS=`pkg-config --cflags libavformat libavcodec libavutil`
all:
	gcc -Wall -g live_segmenter.c -o live_segmenter ${FFFLAGS} ${FFLIBS}

old_ffmpeg:
	gcc -Wall -g live_segmenter.c -o live_segmenter -D USE_OLD_FFMPEG -lavformat -lavcodec -lavutil -lbz2 -lm -lz -lfaac -lmp3lame -lx264 -lfaad -lpthread

clean:
	rm -f live_segmenter
