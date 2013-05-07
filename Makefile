all:
	gcc -L /opt/local/lib -I /opt/local/include -Wall -g live_segmenter.c -o live_segmenter -lavformat -lavcodec -lavutil -lbz2 -lm -lz -lmp3lame -lx264 -lfaad -lpthread

clean:
	rm -f live_segmenter
