.PHONY: dmg clean

dmg:
	./scripts/build-dmg.sh

clean:
	rm -rf build dist dmg-staging
