all:
	gcc -Wall -g live_upload.c -o live_upload -lavformat -lavcodec -lavutil -lbz2 -lm -lz -lfaac -lmp3lame -lx264 -lfaad

clean:
	rm -f live_upload
