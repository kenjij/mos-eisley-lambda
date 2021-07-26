all: build package

build:
	gem i mos-eisley-lambda -Ni ruby/gems/2.7.0
	ls -m ruby/gems/2.7.0/gems

package:
	zip -r lambda-layers ruby -x ".*" -x "*/.*" -x "Makefile"
	zipinfo -t lambda-layers

clean:
	rm -Rfv "ruby"

cleanall: clean
	rm -fv lambda-layers.zip
