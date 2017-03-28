<?php
/**
 * responsible for authentication request from skynet
 * return "code uid", code = 0 means auth success
 */
$mysql_host = "localhost";
$mysql_user = "root";
$mysql_pwd = "";
$mysql_db = "skynetdemo";

$platform = isset($_REQUEST['platform']) ? $_REQUEST['platform'] : "";
$token = isset($_REQUEST['token']) ? $_REQUEST['token'] : "";

$link = mysql_connect($mysql_host, $mysql_user, $mysql_pwd) or die("mysql connect error:" . mysql_error());
mysql_select_db($mysql_db) or die("cant't select database");

$resp = array(
	'code' => -1,
	'uid' => 0,
);

if ($platform == "skynetmud") {
	$arr = explode("\t", $token);

	if (is_array($arr) && sizeof($arr) == 2) {
		$username = $arr[0];
		$password = $arr[1];

		$username_escaped = mysql_escape_string($username);
		$password_escaped = mysql_escape_string($password);

		$sql = "select * from users where username = '%s' and password = '%s' limit 1";
		$sql = sprintf($sql, $username_escaped, $password_escaped);
		$result = mysql_query($sql) or die("mysql query failed: " . $sql);

		$rows = mysql_num_rows($result);
		if ($rows == 1) {
			$row = mysql_fetch_array($result, MYSQL_ASSOC);

			$resp['code'] = 0;
			$resp['uid'] = intval($row['id']);
		}
	}
}

echo $resp['code'] . " " . $resp['uid'];
exit;
