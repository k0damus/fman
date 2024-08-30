#!/usr/bin/env bash
set -o pipefail

fTmp='/tmp/filman'
cookie='/tmp/filman/cookie.txt'
fRaw='/tmp/filman/raw.html'
fLinks='/tmp/filman/links.txt'
sLinksTmp='/tmp/filman/series_links_tmp.txt'
sLinksSel='/tmp/filman/series_links_selected.txt'
outDir="${HOME}"/sciezka/zapisu/pobranych/filmow
fUser='login_usera_do_filmana'
fPass='haslo_usera_do_filmana'

req=('/usr/bin/curl')
reqCheck=()

for r in "${req[@]}"; do
	[ ! -f "${r}" ] && reqCheck+=("${r}");
done

if [ "${#reqCheck[@]}" -gt 0 ]; then
	printf "${reqCheck[*]} <- Brak tych programów. Zainstaluj.\n";
	exit 100
fi

if [ ! -d "${outDir}" ]; then
	printf "Katalog ${outDir} nie istnieje!\n";
	exit 101
fi

while getopts ":l:t:" opt; do
	case "${opt}" in
		l) link="${OPTARG}" ;;
		t) typ="${OPTARG}" ;;
		:) printf "Opcja -${OPTARG} wymaga argumentu.\n" ; exit 900 ;;
		?) printf "Niewłaściwa opcja: -${OPTARG}.\n" ; exit 901
	esac
done

if [ -z "${link}" ] ; then 
	printf "Brak / za malo danych.\n"
	printf "Użycie: ./getvid.sh -l <link_do_strony_z_filmem/serialem_w_serwisie_filman.cc> -t <[lL]ektor / [nN]apisy>\n"
	printf "Parametr opcjonalny:\n"
	printf " -t <typ> - Jeśli parametr zostanie pominięty to pobrana zostanie wersja z lektorem. \n"
	exit 200 
fi

if [[ "${typ}" =~ [nN] ]] ; then
	printf "Wybrano opcję z napisami.\n"
	mediaType='Napisy'
else
	printf "Wybrano opcję z lektorem.\n"
	mediaType='Lektor'
fi

#####################################################
#Tutaj zaczynamy imprezę robiąc porządki jeśli trzeba
rm -rf "${fTmp}" >/dev/null 2>&1 && mkdir "${fTmp}"

#Logowanie do filmana
curl -sL -c "${cookie}" 'https://filman.cc/logowanie' --data-raw "login=${fUser}&password=${fPass}&remember=on&submit=" >/dev/null
curl -sL -c "${cookie}" -b "${cookie}" "${link}" > "${fRaw}"

#Sprawdzamy czy to nie jest aby strona z serialem.
#Na tej podstawie sobie oszacujemy, czy link prowadzi do serialu czy do pojedynczego filmu
seasons_available=$( cat "${fRaw}" | sed -n 's/.*Sezon \([0-9]\{1,\}\).*$/\1/p' | wc -l )

if [ "${seasons_available}" == 0 ]; then
	#Jeśli to nie serial to wyciągamy tytuł
	title=$( cat "${fRaw}" | grep 'og:title' | cut -d '"' -f4 | sed 's/ \/ / /;s/[:;`]//g;s/ /_/g' )
	#A następnie linki dodostępnych VOD
	cat "${fRaw}" | sed 's/^[\t ]*//' | sed -n '/<tbody>/, /<\/tbody>/p' | grep ^\<td | grep -v "center" | tr '\n' ' ' | sed 's/<td /\n<td /g' | grep 720 | grep "${mediaType}" | grep -v IVO | cut -d '"' -f10 | base64 -d | sed 's/}{/}\n{/g' | sed 's/\\//g' | cut -d '"' -f4 > "${fLinks}"
	#Sprawdzamy czy w ogóle mamy linki do wybranej wersji
	if [ -z "$(cat "${fLinks}")" ] ; then
		printf "Brak źródeł dla wybranej wersji: ${mediaType}.\n"
		exit 0
	fi
else
	#Jeżeli to jednak serial, to najpierw szukamy tytułu
	title=$( cat "${fRaw}" | grep 'og:title' | cut -d '"' -f4 | sed 's/ \/ / /;s/[:;`]//g;s/ /_/g' )
	#Potem wyciągamy linki do wszytkich epizodów
	cat "${fRaw}" | sed 's/^[\t ]*//' | sed -n '/<span>Se/,/Komentarze/p' | sed -n 's/.*\(https.*serial-online.*\)">\(.*\)<\/a>.*$/\1;\2/p' | sed 's/ /_/g' > "${sLinksTmp}"
	#Wybór sezonu do ściągnięcia - pytamy użytkownika
	while true; do
		read -p "Ilość znalezionych sezonów serialu: ${seasons_available}. Podaj, który sezon pobrać (1 - ${seasons_available}) lub wpisz w albo W żeby ściągnąć wszystkie sezony: " get_season_no
		#Sprawdzamy czy to co podał jest w ogóle liczbą/cyfrą ORAZ czy mieści się w dostępnym przedziale ilości sezonów (od 1 do ILOŚC_DOSĘPNYCH_SEZONÓW)
		if [[ "${get_season_no}" =~ ^[0-9]+$ ]] && [ "${get_season_no}" -le "${seasons_available}" ]; then 
			#Dodatkowo sprawdzamy czy jest to liczba większa równa bądź większa niż 10, żeby odpowiednio sformatować grepa do wyszukiwania sezonów
			if [ "${get_season_no}" -ge 10 ]; then 
				season_wanted=${get_season_no}
			else
				season_wanted=0${get_season_no}
			fi
			printf "Ściągam sezon: ${get_season_no}.\n"
			#O tego grepa chodzi, tu wyszukujemy sezony z wszystkich dostępnych i zmieniamy nazwy plików, żeby dalej nie rzeźbić za bardzo w kodzie
			cat "${sLinksTmp}" | grep "s${season_wanted}" > "${sLinksSel}" && rm "${sLinksTmp}"
			#I wychodzimy z tej pętli
			break
		#Jeśli użytkownik wybrał opcję ściągnięcia wszystkiego, to po prostu zmieniamy nazwy plików i lecimy dalej
		elif [[ "${get_season_no}" == [wW] ]]; then
			printf "Ściągam wszystkie sezony.\n"
			mv "${sLinksTmp}" "${sLinksSel}"
			break
		#A jak nic nie podał, to będziemy wyświetlać pytanie aż do skutku
		else
			printf ""
		fi
	done

	#Następnie w pętli wyszukujemy linki VOD dla każdego odcinka i zapisujemy je do folderu /tmp/filman do pliku o nazwie: serial.tytulSerialu.tytulOdcinka.txt
	printf "Szukam odnośników do odcinków...\n"
	while read line; do 
		curl -sL -c "${cookie}" -b "${cookie}" $(printf "${line}" | cut -d ';' -f1) | sed 's/^[\t ]*//' | sed -n '/<tbody>/, /<\/tbody>/p' | grep ^\<td | grep -v "center" | tr '\n' ' ' | sed 's/<td /\n<td /g' | grep 720 | grep "${mediaType}" | grep -v IVO | cut -d '"' -f10 | base64 -d | sed 's/}{/}\n{/g' | sed 's/\\//g' | cut -d '"' -f4 > "${fTmp}"/serial."${title}".$(printf "${line}" | cut -d ';' -f2).txt
		if [ ! -s  "${fTmp}"/serial."${title}".$(printf "${line}" | cut -d ';' -f2).txt ] ; then
			printf "Brak źródeł dla wybranej wersji: ${mediaType} dla: ${title}.$(printf "${line}" | cut -d ';' -f2) \n"
		fi
	done<"${sLinksSel}" 
fi

#Tworzy katalog tymczasowy do ściągania części filmu / odcinka serialu
make_dir(){
	mkdir -p "${fTmp}"/"${1}"_temp
	tmpDir="${fTmp}/${1}_temp"
	touch "${tmpDir}"/parts.txt
	partsList="${tmpDir}"/parts.txt
}

#Obsługa pobierania z różnych VOD
voe(){
	followUp=$( curl -sL "${link}" | sed -n "s/^.*\(https.*\)'.*$/\1/p" | head -n 1 ) #1. Obejście, żeby z linka voe dostać się do właściwej strony voe.
	fullURL=$( curl -sL "${followUp}" | grep nodeDetails | cut -d '"' -f4) #2. Z wyniku tego wyżej wyciągamy właściwy link do listy m3u8.
	mainURL=$( printf "${fullURL}" | sed -n 's/\(^.*\)\/master.*$/\1/p') #3. Link do segmentów to  2 części: link główny + linki do segmentów. Tutaj robimy część główną - z wyniku z poprzeniego polecenia.
	partsPATH=$( curl -sL "${fullURL}" | grep ^index ) #4. Wyszukujemy link do "playlisty".
	curl -sL "${mainURL}"/"${partsPATH}" | grep -v ^# > "${partsList}" #5. Łącząc wyniki kroku (3) i (4) mamy link do playlisty, z której wybieramy segmenty.
}

vidoza(){
	mkdir "${outDir}"/"${title}"
	videoURL=$( curl -sL "${link}" | grep sourcesCode | cut -d '"' -f2 )
	curl "${videoURL}" -o "${outDir}"/"${title}"/"${title}".mp4
	printf "\n\nFilm zapisany w ${outDir}/${title}/${title}.mp4 \n\n"
}

dood(){
	passUrl=$( curl -sL "${link}" | sed -n 's/.*\(\/pass\_md5\/[-0-9a-z\/]*\).*$/\1/p')
	tokenUrl=$( printf "${passUrl}" | cut -d '/' -f4 )
	tempUrl=$( curl -sL $( printf https://d0000d.com${passUrl} ) -H "referer: $( printf "${link}" | sed 's/dood.yt/d0000d.com/g')" )
	randomString=$( cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1 )
	validUrl=$( printf ${tempUrl}${randomString}"?token="${tokenUrl}"&expiry="$(date +%s)) 
	curl -L "${validUrl}" -H "referer: $( printf "${link}" | sed 's/dood.yt/d0000d.com/g')" -o "${outDir}"/"${seriesTitle}"/"${seasonNumber}"/"${episodeTitle}".ts
	printf "\n\nFilm zapisany w ${outDir}/${seriesTitle}/${seasonNumber}/${episodeTitle}.ts \n\n"
}

upstream(){
	curl -sL "${link}" | grep 'p,a,c,k,e,d' | sed 's/<[^>]*>//g' > "${tmpDir}"/js.tmp
	nodejs "${tmpDir}"/js.tmp 2>"${tmpDir}"/js.tmp.error
	fullURL=$( cat "${tmpDir}"/js.tmp.error | sed -n 's/^.*file:"\(https.*\)"}],image.*$/\1/p' )
	mainURL=$( printf "${fullURL}" | sed -n 's/\(^.*\)\/master.*$/\1/p')
	partsPATH=$( printf "${fullURL}" | sed 's/master/index-a1-v1/')
	curl -s "${partsPATH}" | grep -v ^# | sed 's/^.*seg/seg/g' > "${partsList}"
}

streamvid(){
	curl -sL "${link}" | grep 'p,a,c,k,e,d' | sed 's/<[^>]*>//g' > "${tmpDir}"/js.tmp
	nodejs "${tmpDir}"/js.tmp 2>"${tmpDir}"/js.tmp.error
	segURL=$( curl -s $( cat "${tmpDir}"/js.tmp.error | sed -n 's/^.*src:"\(https.*\)",type.*$/\1/p' ) | grep index )
	mainURL=$( printf "${segURL}" | sed 's/\/index-v1-a1.m3u8//g' )
	curl -s "${segURL}" | grep -v ^# > "${partsList}"
}

#Obsługa pobrania POJEDYNCZEGO filmu
getVideo(){
	ilosc=$( cat "${partsList}" | wc -l )
	count=1;
		while read line ; do
		        nazwa=$(printf "%03d" "${count}");
		        printf "Pobieram część ${count} z ${ilosc}\n"
    			curl -s "${mainURL}"/"${line}" -o "${tmpDir}"/"${nazwa}".ts
		        count=$((count+1))
		done<"${partsList}"

	mkdir "${outDir}"/"${title}"
	cat $(ls "${tmpDir}"/*.ts) > "${outDir}"/"${title}"/"${title}".ts 
	printf "\n\nFilm zapisany w ${outDir}/${title}/${title}.ts \n\n"
}

#Obsługa pobierania seriali - ładuje filmy do wcześniej przygotowanej struktury katalogów, wedle schematu:
#${outDir}/Tytul:
#- s01
#  	- [s01e01].tytul.mp4/mpg
#	- [s01e02].tytul.mp4/mpg
#	- ...
# - s02
#	- [s02e01].tytul.mp4/mpg
#	- [s02e02].tytul.mp4/mpg
#	- ...
getSeries(){
	ilosc=$( cat "${partsList}" | wc -l )
	count=1;

		while read line ; do
				nazwa=$(printf "%03d" "${count}");
				printf "Pobieram część ${count} z ${ilosc}\n"
				curl -s "${mainURL}"/"${line}" -o "${tmpDir}"/"${nazwa}".ts
				count=$((count+1))
		done<"${partsList}"

	cat $(ls "${tmpDir}"/*.ts) > "${outDir}"/"${seriesTitle}"/"${seasonNumber}"/"${episodeTitle}".ts 
	printf "\n\nFilm zapisany w ${outDir}/${seriesTitle}/${seasonNumber}/${episodeTitle}.ts \n\n"
}

#Sprawdzamy z którego serwisu możemy pobrać dany film. Preferowane jest voe.
#Funkcja sprawdza po kolei czy dane serwis znajduje się na liście z linkami do filmu
#Jeśli istnieje to wybiera dany link do pobierania o przypisuje do zmiennej link ORAZ myVod - to wyjaśnione poniżej. Tu następuje wyjście z pętli.
#Jeśli nie istnieje to szuka następnego z listy vods, aż do skutku.
#voe - najszybsze pobieranie
#vidoza - jw, ale mniej popularny serwis chyba
#dood - ograniczone pobieranie, bardzo popularny serwis
#upstream - meh
#streamvid - meh
vodCheck(){
	#Lista w preferowanej kolejności serwisów
	vods=('voe' 'vidoza' 'dood' 'upstream' 'streamvid')
	for v in "${vods[@]}"; do
		isThere=$( grep "${v}" "${1}" | head -n 1 )
		if [ ! -z $isThere ]; then
			myVod="${v}"
			link="${isThere}"
		break
		fi
	done
}

#CZĘŚĆ GŁÓWNA
#Sprawdzamy czy ISTNIEJE i NIE JEST PUSTY plik z linkami do serialu
if [ ! -s "${sLinksSel}" ]; then
	#Jeśli nie to ściągamy film
	make_dir "${title}"		#Tworzymy jatalog tymczasowy
	vodCheck "${fLinks}"	#Szukamy dostępnego vod
	printf "Pobieram ${title} z ${myVod}...\n\n"	#Informujemy skąd będziemy ściągać
		if [ "${myVod}" == 'dood' ] || [ "${myVod}" == 'vidoza' ] ; then	#Jeśli wybrany/znaleziony vod to dood albo vidoza, to odpalamy tylko jego funkcję, bo ponieważ stamtąd ściągamy nieco inaczej
			"${myVod}"
		else								#A jeśli nie, to odpalamy funkcję konkretnego vod, a potem getVideo
			"${myVod}"
			getVideo						#Funkcja do pobierania pojedynczego filmu
		fi
else
	#Jeśli są dane serialowe to robimy to poniżej    
	for i in $( ls "${fTmp}" | grep 'serial\.' ); do
		if [ ! -z  "$( cat "${fTmp}"/"${i}" )" ] ; then
			seriesTitle=$( printf "${fTmp}"/"${i}" | cut -d '.' -f2) #Wybieramy tytul serialu
			episodeTitle=$( printf "${fTmp}"/"${i}" | cut -d '.' -f3) #Wybieramy tytul odcinka
			seasonNumber=$( printf "${episodeTitle}" | sed -n 's/^\[\([sS][0-9]\{1,2\}\).*$/\1/p') #Wybieramy znacznik sezonu w postaci: sXX / SXX
			[ ! -d "${outDir}"/"${seriesTitle}"/"${seasonNumber}" ] && mkdir -p "${outDir}"/"${seriesTitle}"/"${seasonNumber}" #Tworzymy katalog: $outDir/seriesTitle/seasonNumber, jeżeli nie istnieje.

			if [ ! -s "${outDir}/${seriesTitle}/${seasonNumber}/${episodeTitle}.ts" ] ; then #Sprawdzamy czy plik: $outDir/seriesTitle/seasonNumber/episodeTitle.ts istnieje. Jeżeli nie to odpalamy procedurę ściągania.

				make_dir "${episodeTitle}"				#Tworzymy folder tymczasowy dla odcinka
				mv "${fTmp}"/"${i}" "${tmpDir}"		#Wrzucamy tam plik z linkami do odcinka
				vodCheck "${tmpDir}"/"${i}"			#Wybieramy vod

				printf "Pobieram ${episodeTitle} z ${myVod}...\n\n"	#Informujemy skąd będziemy ściągać
				if [ "${myVod}" == 'dood' ] || [ "${myVod}" == 'vidoza' ] ; then	#Jeśli wybrany/znaleziony vod to dood albo vidoza, to odpalamy tylko jego funkcję, bo ponieważ stamtąd ściągamy nieco inaczej
					"${myVod}"
				else
					"${myVod}"
					getSeries #Zmodyfikowana funkcja getVideo, aby odpowiednio zapisywać odcinki w strukturze katalogów.
				fi
				rm -rf "${tmpDir}"					#Wywalamy tymczasowy katalog dla odcinka
			fi
		fi
	done
fi

#No i robimy porządki na koniec
rm -rf "${fTmp}"
