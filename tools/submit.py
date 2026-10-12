#!/usr/bin/env python3
"""えさやり帳の最初の版を App Store の審査に出す。

    ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=... python3 tools/submit.py <審査連絡用の電話番号>
    （--dry を付けると、最後の提出だけ行わない）

App Store Connect のアプリの枠と「App のプライバシー」は Web で先に作っておく（API では作れない）。
API の呼び出しは MiniCity の gcachievements を借りる。
"""
import hashlib, json, os, subprocess, sys, tempfile, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.expanduser("~/pj/minicity/gcachievements")
TEAM, BUNDLE = "B54UXU8NGQ", "com.shuyafukai.esayari"
WORK = tempfile.mkdtemp(prefix="esayari-")
SITE = "https://nakiusa.github.io/esayari/"
DESCRIPTION = """「えさやり帳」は、魚や水槽ごとにえさをあげた時刻を記録し、次のえさの時刻に通知で知らせるアプリです。

■ 使いかた
・魚や水槽を登録し、えさの間隔（1〜168時間）を決めます
・えさをあげたら「あげた」を押します
・次のえさの時刻になると通知が届きます。一覧では時間を過ぎた魚が上に並び、色で分かります

■ 記録
魚ごとに、えさをあげた日時の記録が残ります。押し間違えた記録は消せます。

■ プライバシー
記録は端末の中にだけ保存します。登録もログインも要りません。広告もありません。"""
KEYWORDS = "えさ,餌,熱帯魚,金魚,メダカ,アクアリウム,水槽,ベタ,グッピー,リマインダー,通知,記録,ペット,飼育"


def asc(method, path, body=None):
    if body is None:
        out = subprocess.run([TOOL, "--get", path], capture_output=True, text=True)
    else:
        f = os.path.join(WORK, "body.json")
        json.dump(body, open(f, "w"), ensure_ascii=False)
        out = subprocess.run([TOOL, "--send", method, path, f], capture_output=True, text=True)
    if out.returncode:
        sys.exit(f"{method} {path} に失敗\n{out.stdout[-2000:]}\n{out.stderr[-2000:]}")
    return json.loads(out.stdout) if out.stdout.strip() else {}


def patch(kind, id, attrs):
    asc("PATCH", f"/v1/{kind}/{id}", {"data": {"type": kind, "id": id, "attributes": attrs}})


def upload_build():
    auth = ["-allowProvisioningUpdates", "-authenticationKeyPath", os.environ["ASC_KEY_PATH"],
            "-authenticationKeyID", os.environ["ASC_KEY_ID"], "-authenticationKeyIssuerID", os.environ["ASC_ISSUER_ID"]]
    archive, options = os.path.join(WORK, "Esayari.xcarchive"), os.path.join(WORK, "options.plist")
    open(options, "w").write(f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>upload</string>
<key>teamID</key><string>{TEAM}</string>
<key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>""")
    subprocess.run(["xcodegen", "generate", "-q"], cwd=ROOT, check=True)
    for args in (["-project", "Esayari.xcodeproj", "-scheme", "Esayari", "-configuration", "Release",
                  "-destination", "generic/platform=iOS", "-archivePath", archive, "archive"],
                 ["-exportArchive", "-archivePath", archive, "-exportOptionsPlist", options,
                  "-exportPath", os.path.join(WORK, "export")]):
        out = subprocess.run(["xcodebuild", *args, *auth], cwd=ROOT, capture_output=True, text=True)
        if out.returncode:
            sys.exit(out.stdout[-3000:] + out.stderr[-3000:])
    print("ビルドを上げた")


def upload_screenshots(loc_id):
    sets = asc("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")["data"]
    found = [s for s in sets if s["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67"]
    if found:
        set_id = found[0]["id"]
        for shot in asc("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots")["data"]:
            asc("DELETE", f"/v1/appScreenshots/{shot['id']}", {})
    else:
        set_id = asc("POST", "/v1/appScreenshotSets", {"data": {
            "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"},
            "relationships": {"appStoreVersionLocalization": {"data": {
                "type": "appStoreVersionLocalizations", "id": loc_id}}}}})["data"]["id"]
    folder = os.path.join(ROOT, "screenshots")
    for name in sorted(os.listdir(folder)):
        data = open(os.path.join(folder, name), "rb").read()
        shot = asc("POST", "/v1/appScreenshots", {"data": {
            "type": "appScreenshots", "attributes": {"fileName": name, "fileSize": len(data)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
        for op in shot["attributes"]["uploadOperations"]:
            part = data[op["offset"]:op["offset"] + op["length"]]
            req = urllib.request.Request(op["url"], data=part, method=op["method"],
                                         headers={h["name"]: h["value"] for h in op["requestHeaders"]})
            urllib.request.urlopen(req).read()
        patch("appScreenshots", shot["id"], {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()})
    print("スクリーンショットを上げた")


def main():
    phone, dry = sys.argv[1], "--dry" in sys.argv
    app = asc("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")["data"]
    if not app:
        sys.exit("App Store Connect にアプリの枠がない。Web で新規App を作ってから流す。")
    app_id = app[0]["id"]
    patch("apps", app_id, {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"})

    # アプリ全体の情報：カテゴリ、サブタイトル、プライバシーポリシー、年齢制限。
    info = asc("GET", f"/v1/apps/{app_id}/appInfos")["data"][0]["id"]
    asc("PATCH", f"/v1/appInfos/{info}", {"data": {"type": "appInfos", "id": info, "relationships": {
        "primaryCategory": {"data": {"type": "appCategories", "id": "LIFESTYLE"}}}}})
    for loc in asc("GET", f"/v1/appInfos/{info}/appInfoLocalizations")["data"]:
        patch("appInfoLocalizations", loc["id"], {"subtitle": "魚のえさの時刻を忘れない",
                                                  "privacyPolicyUrl": SITE + "privacy.html"})
    rating = asc("GET", f"/v1/appInfos/{info}/ageRatingDeclaration")["data"]
    # 質問はすべて「なし」。項目は Apple が増やすので、いま返ってきたものに合わせて埋める。
    # 値がまだ空（None）の項目は型が分からないので、エラーが出たらその名前を見て足す。
    patch("ageRatingDeclarations", rating["id"],
          {k: False if isinstance(v, bool) else "NONE" for k, v in rating["attributes"].items()
           if isinstance(v, (bool, str)) and "Override" not in k and k not in ("kidsAgeBand", "developerAgeRatingInfoUrl")})
    print("アプリの情報を入れた")

    version = asc("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[appStoreState]=PREPARE_FOR_SUBMISSION")["data"][0]
    vid = version["id"]
    patch("appStoreVersions", vid, {"versionString": "1.0.0", "copyright": "2026 Shuya Fukai"})
    loc = asc("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"][0]
    patch("appStoreVersionLocalizations", loc["id"], {"description": DESCRIPTION, "keywords": KEYWORDS,
                                                      "supportUrl": SITE, "marketingUrl": SITE})
    upload_screenshots(loc["id"])

    review = {"contactFirstName": "Shuya", "contactLastName": "Fukai", "contactEmail": "icoca.de.suica@gmail.com",
              "contactPhone": phone, "demoAccountRequired": False}
    existing = asc("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
    if existing:
        patch("appStoreReviewDetails", existing["id"], review)
    else:
        asc("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": review,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    print("審査用の連絡先を入れた")

    upload_build()
    for _ in range(80):
        builds = asc("GET", f"/v1/builds?filter[app]={app_id}&filter[version]=1"
                            f"&filter[preReleaseVersion.version]=1.0.0")["data"]
        if builds and builds[0]["attributes"]["processingState"] == "VALID":
            break
        time.sleep(15)
    else:
        sys.exit("ビルドの処理が終わらない")
    asc("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": builds[0]["id"]}})
    print("ビルドを付けた")
    if dry:
        return print("--dry なので提出はしない")

    sid = asc("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]["id"]
    asc("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    state = asc("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {
        "type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})["data"]["attributes"]["state"]
    print("審査に出した:", state)


if __name__ == "__main__":
    main()
