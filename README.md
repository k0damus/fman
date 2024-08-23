# Pobierak z filmana

Do edycji wedle własnych potrzeb linijka 9, 10 i 11

`outDir="${HOME}"/Wideo`

`fUser='login_usera_do_filmana'`

`fPass='haslo_usera_do_filmana'`


Użytkowanie:

`getvid.sh -l <link_do_strony_z_filmem/serialem_w_serwisie_filman.cc> -t <[lL]ektor / [nN]apisy>`

np.:

`getvid.sh -l https://filman.cc/serial-online/2949/jakis-tam-serial -t l`

Spowoduj wyszukanie linków do odcinków konkretnego serialu wedle parametrów: 

`-t l -> lektor`

Uprzednio zostanie wyświetlona informacja o tym, ile sezonów znaleziono oraz zapytanie ile z tych sezonów ściągnąć. Jest możliwość ściągnięcia konkrentego sezonu, ale też wszystkiego od razu.

Jeśli chcemy ściągać serial to trzeba podać link do strony z rozpiską wszystkich sezonów, a nie link do strony z konkretnym sezonem/odcinkiem.

Więcej komentarzy w kodzie.
