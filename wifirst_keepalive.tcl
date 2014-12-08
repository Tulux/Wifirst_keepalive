# wifirst_keepalive.tcl
# Purpose: Keeping Wifirst connection alive despite constant logouts. Don't forget to put your own login/password below.
#
# Author: Florent DELAHAYE <delahaye.florent@gmail.com>
# Date: 2014-05-09
# Version: 1.0
#
# Require: Tcl, cUrl command
# Execution: tclsh wifirst_keepalive.tcl



# Display debug informations
proc superputs {str} {

	global debug
	
	if {$debug} {
		puts $str
	}
}

# Encode string for url using UTF8 (block 1+2: 256 chars)
proc url_encode {str} {

        variable map
        variable alphanumeric a-zA-Z0-9

        # Basic Latin
        for {set i 0} {$i <= 256} {incr i} {
                set c [format %c $i]
                if {![string match \[$alphanumeric\] $c]} {
                        if {$i > 127 && $i < 192} {
                                set map($c) %C2%[format %.2x $i]
                        } elseif {$i >= 192} {
                                set map($c) %C3%[format %.2x [expr $i-64]]
                        } else {
                                set map($c) %[format %.2x $i]
                        }
                }
        }

        # These are handled specially
        array set map {" " + \n %0d%0a "€" %e2%82%ac}

        regsub -all \[^$alphanumeric\] $str {$map(&)} {str}
        regsub -all {[][{})\\]\)} $str {\\&} {str}

        return [subst -nocommand $str]
}

# Connection through wifirst interface with login and password
proc connector {login pass} {

	global curl
	global cookieFile

	# Step 1: get authenticity token
	superputs "Step 1: Getting authenticity token..."

	catch {exec {*}$curl -c $cookieFile "https://selfcare.wifirst.net/sessions/new"} page
	regexp "name=\"authenticity_token\" type=\"hidden\" value=\"(\[a-zA-Z0-9/+=\]*)\"" "$page" _ token

	superputs "OK"

	# Step 2: send login/pass and authenticity token
	superputs "Step 2: Authenticating..."

	set postdata "utf8=%E2%9C%93&authenticity_token=[url_encode $token]&login=$login&password=$pass&commit=Sign+in&remember_me=0"

	catch {exec {*}$curl  -b $cookieFile -c $cookieFile -d $postdata "https://selfcare.wifirst.net/sessions"} page
	catch {exec {*}$curl -b $cookieFile -c $cookieFile "https://connect.wifirst.net/?perform=true"} page

	superputs "OK"

	# Step 3: extract temporary username/password from response and re-inject them into another page
	superputs "Step 3: Validating..."

	regexp "name=\"username\" type=\"hidden\" value=\"(\[a-zA-Z0-9/\]+@wifirst.net)\"" "$page" _ username
	regexp "name=\"password\" type=\"hidden\" value=\"(\[a-fA-F0-9\]*)\"" "$page" _ password

	set postdata2 "username=[url_encode $username]&password=$password&qos_class=0&success_url=https%3A%2F%2Fapps.wifirst.net%2F%3Fredirected%3Dtrue&error_url=https%3A%2F%2Fconnect.wifirst.net%2Flogin_error&commit=Se+connecter"

	catch {exec {*}$curl -b $cookieFile -c $cookieFile -d $postdata2 "https://wireless.wifirst.net:8090/goform/HtmlLoginRequest"} page

	superputs "OK"
}

###########################################################################
#
#
#			Entry point
#
#
###########################################################################

set login "YOUR_LOGIN"
set pass "YOUR_PASSWORD"

set debug 1
set testPage "google.fr"
set curlPath "/usr/bin/curl"
set userAgent "Mozilla/5.0"
set curlArgs "-s -k -L -A $userAgent"
set curl "$curlPath $curlArgs"
set cookieFile cookie.txt


while {1} {
	superputs "Test pending..."

	catch {exec {*}$curl -m 5 $testPage} page

	# Looking for "wifirst" keyword inside response
	if {[string first "connect.wifirst.net" "$page"] != -1} {
		superputs "Connection lost"
		connector $login $pass
		superputs "Connection recovered"
	} else {
		superputs "Ok"
	}
	
	# Sleep 10s
	after 10000
}
