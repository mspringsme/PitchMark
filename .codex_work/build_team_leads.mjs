import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const outputDir = "/Users/markspringer/Documents/PitchMark/outputs/il_wi_team_leads_2026";
const outputPath = `${outputDir}/Illinois_Wisconsin_Baseball_Fastpitch_Leads_2026.xlsx`;
const checked = "2026-08-24";

const leads = [
  [1,"Lake County Lightning Baseball","Baseball","IL","Mundelein / Grayslake","Chicago / North Suburbs","8U-18U","Jeremy Lutz","Director","info@illinoislightningbaseball.com","Role inbox","Email","https://lakecountylightning.com/contact/","https://www.facebook.com/illinoislightningbaseball/","https://www.instagram.com/illinois_lightning/","https://twitter.com/ILlightning","2026-27 program and tryouts active","High",checked,"Not contacted","Current official contact page"],
  [2,"Illinois Lightning Softball","Fastpitch","IL","Lake County","Chicago / North Suburbs","9U-18U","Kurt Hironimus","Director","","Contact page","Instagram / Facebook DM","https://lakecountylightning.com/contact/","https://www.facebook.com/IlLightning","https://www.instagram.com/illinois_lightning_softball/","https://twitter.com/softball_il","2026-27 program and tryouts active","High",checked,"Not contacted","Official social links published on contact page"],
  [3,"Tier 1 Elite Baseball","Baseball","IL","Elgin","Fox Valley / Northwest","14U-18U","Organization","Tryouts","tier1elitebaseball@gmail.com","Organization inbox","Email","https://www.tier1elite.com/tryouts","","","","2027 tryouts posted","High",checked,"Not contacted","Private-tryout contact is public"],
  [4,"Frankfort Force","Baseball","IL","Frankfort","Southwest Suburbs","8U-15U","Joe Wodark","Travel Director","travelballdirector@frankfortbaseball.com","Role inbox","Email","https://www.frankfortbaseball.com/Default.aspx?tabid=1709802","","","","2027 tryouts posted","High",checked,"Not contacted","Organization travel director"],
  [5,"Deerfield Travel Baseball","Baseball","IL","Deerfield","Chicago / North Suburbs","8U-14U","Travel Baseball","Program","travel.baseball@dyba.com","Role inbox","Email","https://www.dyba.com/page/show/7805686-travel-baseball-2023-","","","","2027 tryouts posted","High",checked,"Not contacted","Role-based travel email"],
  [6,"Lincoln-Way Blue Demons","Baseball","IL","Mokena / New Lenox","Southwest Suburbs","Multiple youth","Frank Lacny","Organization contact","flacny@lwbluedemons.org","Director email","Email","https://www.lwbluedemons.org/","","","","2027 teams and tryouts posted","High",checked,"Not contacted","Current organization contact"],
  [7,"Cary Trojans","Baseball","IL","Cary","Northwest Suburbs","Multiple youth","Kyle Frangiamore","Travel Director","traveldirector@cgybs.org","Role inbox","Email","https://trojansbaseballandsoftball.com/tryouts/","","","","2026-27 tryouts posted","High",checked,"Not contacted","Program seeks additional teams/coaches"],
  [8,"Washington Youth Travel Baseball","Baseball","IL","Washington","Central Illinois","7U-17U","WYTB Committee","Program","wytb@washingtontravelbaseball.com","Role inbox","Email","https://washingtontravelbaseball.com/","","","","2027 tryouts posted","High",checked,"Not contacted","Organization-wide inbox"],
  [9,"USA Prime Northern Illinois","Both","IL","South Elgin","Fox Valley / Northwest","9U-18U","Todd Lambel","Program contact","todd@usaprimeni.com","Director email","Email","https://www.usaprimeni.com/tryouts","","","","2027 baseball and softball tryouts posted","High",checked,"Not contacted","One contact reaches baseball and softball"],
  [10,"Vernon Hills Travel Baseball","Baseball","IL","Vernon Hills","Chicago / North Suburbs","8U-14U","Travel Baseball","Program","travel_baseball@vhcbs.com","Role inbox","Email","https://www.vhcbs.org/program/travel-baseball/18032","","","","2027 tryouts posted","High",checked,"Not contacted","Role-based travel email"],
  [11,"Skokie Coyotes","Baseball","IL","Skokie","Chicago / North Suburbs","8U-14U","Chris Librando","Travel Director","chrislibrando@gmail.com","Director email","Email","https://skokiebaseballandsoftball.com/2025/06/28/coyotes-travel-baseball-tryouts-2026-season/","","","","2026 program verified; page current in 2026","Medium",checked,"Not contacted","General inbox also: skokiebaseballandsoftball@gmail.com"],
  [12,"Hamlin Park Travel","Both","IL","Chicago","Chicago","8U-14U","Travel Teams","Program","travelteams@hamlinparkbaseball.org","Role inbox","Email","https://www.hamlinparkbaseball.org/2027traveltryouts","","","","2027 baseball and softball tryouts posted","High",checked,"Not contacted","One role inbox reaches both sports"],
  [13,"Christian Center Travel Baseball","Baseball","IL","Peoria / East Peoria","Central Illinois","8U-17U","Travel Baseball","Program","travelbaseball@thechristiancenter.cc","Role inbox","Email","https://www.thechristiancenter.cc/registration/travel-baseball/","","","","2027 tryouts posted","High",checked,"Not contacted","Central Illinois coverage"],
  [14,"Limestone Youth Baseball Travel","Baseball","IL","Bartonville","Central Illinois","8U-15U","Travel Program","Program","limestoneyouthbaseball@gmail.com","Organization inbox","Email","https://www.limestoneyouthbaseball.org/travel-program","https://www.facebook.com/limestoneyouthbaseball/","","","2027 tryouts posted","High",checked,"Not contacted","Official page points to Facebook"],
  [15,"Rawlings Tigers Southern Illinois","Both","IL","Southern Illinois","Southern Illinois","Multiple youth","Area program","Organization","","Official page / follow","Website contact","https://www.rawlingstigers.com/teams/illinois/southern-illinois","","","","2027 teams and openings posted","High",checked,"Not contacted","Eight current teams shown; use area page"],
  [16,"Tinley Park Bulldogs","Baseball","IL","Tinley Park","South Suburbs","8U-15U","Glenn Kendall","Assistant Travel Director","gkbaseball4@gmail.com","Director email","Email","https://www.tinleyparkbulldogsbaseball.com/bbtryouts","","","","2027 tryouts and openings posted","High",checked,"Not contacted","Current travel director contact"],
  [17,"Roselle Rockers","Fastpitch","IL","Roselle","West / Northwest Suburbs","10U-18U","Al / Ray Kubalewski","Travel Director","raykubalewski@gmail.com","Director email","Email","https://www.rockersfastpitch.com/","","","","2026-27 tryouts posted","High",checked,"Not contacted","Director email public on official site"],
  [18,"Illinois Force Softball","Fastpitch","IL","Southern Illinois","Southern Illinois","Multiple youth / HS","Scott Hutchinson","Owner","scott.hutchinson@ilforce.com","Director email","Email","https://ilforce.com/","https://ilforce.com/?page_id=482","","","2026 results and 2027 tryout activity","High",checked,"Not contacted","Media page links social channels"],
  [19,"Illinois Wave Fastpitch","Fastpitch","IL","Gurnee / Warren Township","Chicago / North Suburbs","Multiple youth","Travel Program","Program","travel@warrengirlssoftball.com","Role inbox","Email","https://warrengirlssoftball.sportngin.com/register/form/441311187","","","","2026-27 tryouts posted","High",checked,"Not contacted","Role-based travel email"],
  [20,"Carol Stream Storm","Fastpitch","IL","Carol Stream / West Chicago","West Suburbs","Multiple youth","Storm Softball","Program","cstsba.softball@gmail.com","Organization inbox","Email","https://www.cstsba.com/softballtryouts","","","","2026-27 tryouts posted","High",checked,"Not contacted","Program also publishes president inbox"],
  [21,"Kishwaukee Valley Storm","Fastpitch","IL","Kingston / DeKalb area","Northern Illinois","Multiple youth","Organization","Program","","Official website","Website / social links","https://kvstorm.org/","","","","2027 teams and tryouts active","High",checked,"Not contacted","Current official site; use its inquiry/social links"],
  [22,"K25 Pride Softball","Fastpitch","IL","North Aurora","Fox Valley / West Suburbs","8U-14U","Lily","Program contact","lily@k25baseball.com","Role inbox","Email","https://www.k25baseball.com/pride-softball","","","","2026-27 tryouts posted","High",checked,"Not contacted","One inbox for program and incoming teams"],
  [23,"CTW Softball","Fastpitch","IL","Crystal Lake / McHenry","Northwest Suburbs","Multiple youth","Program contact","Program","pghempen@gmail.com","Program contact","Email","https://www.ctwfastpitch.com/page/show/735634-2025-2026-tryouts","","","","2026-27 tryouts posted","High",checked,"Not contacted","Current tryout contact"],
  [24,"Silver Hawks Softball Association","Fastpitch","IL","West Chicago","West Suburbs","12U-18U","Shaun Cavazos","Coach contact","cavazos2877@gmail.com","Coach email","Email","https://silverhawksfastpitch.sportngin.com/","","","","2026-27 teams and coaches posted","High",checked,"Not contacted","Team-specific public contact; personalize outreach"],
  [25,"Illinois Valley Aftershock","Fastpitch","IL","Peru / Illinois Valley","North-Central Illinois","9U-16U","Organization","Program","","Official website / Facebook","Facebook via website","https://www.illinoisvalleyaftershock.com/","","","","2025-26 teams and 2026 schedules posted","High",checked,"Not contacted","Official site links Facebook and current team pages"],
  [26,"Illinois Sluggers","Fastpitch","IL","Schaumburg","Northwest Suburbs","Multiple youth / HS","Dan Long","Head Commissioner","","Official program page","Website contact","https://www.saa-online.com/sluggers","","","","2025-26 teams and current program page","Medium",checked,"Not contacted","Use commissioner/contact route on official page"],
  [27,"Express Fastpitch","Fastpitch","IL","Monroe Center","Northern Illinois","Multiple youth","Organization","Program","expressfastpitch2010@gmail.com","Organization inbox","Email","https://www.expressfastpitch.com/","","","","Official site; contact references 2024-25","Medium",checked,"Not contacted","Verify activity before larger send"],
  [28,"Woodstock Storm","Fastpitch","IL","Woodstock","Northern Illinois","10U-16U","Storm Program","Program","","Official contact page","Website contact","https://www.woodstockgirlssoftball.org/Default.aspx?tabid=970475","","","","Current program page crawled 2026","Medium",checked,"Not contacted","Email is obscured publicly; use page contact"],
  [29,"Lady Reds Softball","Fastpitch","IL","Northern Illinois","Northern Illinois","18U","Organization","Team","ctmblnsn@gmail.com","Team inbox","Email","https://www.ladyredsil.org/","","","","Current site crawled 2026","Medium",checked,"Not contacted","Single-team lead"],
  [30,"Silver Sluggers Academy","Both","WI","Middleton / Lake Mills","South-Central Wisconsin","Multiple youth","Organization","Academy","support@silversluggers.com","Role inbox","Email","https://silversluggers.com/","","","","2026-27 expansion and tryouts active","High",checked,"Not contacted","Two locations and both sports"],
  [31,"Puma Baseball Academy","Both","WI","Kenosha","Southeast Wisconsin","Multiple youth","Organization","Academy","admin@pumabaseballacademy.com","Role inbox","Email","https://www.pumabaseballacademy.com/","","","","Current travel-team program","High",checked,"Not contacted","Both sports; organization inbox"],
  [32,"Hitters Baseball Academy","Baseball","WI","Caledonia / Menomonee Falls","Southeast Wisconsin","Youth / HS","Andy","Organization contact","andy@hittersbaseball.org","Organization email","Email","https://hittersbaseballacademy.com/","","","","Current site with 2026/2027 players","High",checked,"Not contacted","Large program with two locations"],
  [33,"West Madison Thunder","Both","WI","Madison","South-Central Wisconsin","8U-14U","Tryouts","Program","tryouts@westmadisonthunder.com","Role inbox","Email","https://www.westmadisonthunder.com/program/thunder-baseball/22672","","","","2027 baseball and softball programs active","High",checked,"Not contacted","Same inbox reaches both programs"],
  [34,"Northwoods Baseball Select","Baseball","WI","Kronenwetter / Wausau area","Central Wisconsin","9U-14U","Matt Spets","Program contact","northwoodsbaseballllc@gmail.com","Organization inbox","Email","https://www.nwbaseballselect.org/events-1/2026-northwoods-baseball-tryouts","","","","2027 tryouts posted","High",checked,"Not contacted","Current north-central lead"],
  [35,"Mosinee Youth Baseball","Baseball","WI","Mosinee","Central Wisconsin","8U-14U","Brad Pochinski","Travel Manager","mosineeyouthbaseball@gmail.com","Organization inbox","Email","https://www.mosineeyouthbaseball.com/news/2027-travel-league-registration/17923","","","","2027 registration and coaches posted","High",checked,"Not contacted","Role/organization inbox"],
  [36,"Turn 2 Athletics","Baseball","WI","Altoona / Eau Claire","Western Wisconsin","14U-16U","Organization","Program","baseball@turn2-athletics.com","Role inbox","Email","https://www.turn2-athletics.com/baseball","","","","2027 travel tryouts posted","High",checked,"Not contacted","Western Wisconsin coverage"],
  [37,"Slinger On Base Baseball Club","Baseball","WI","Slinger","Southeast Wisconsin","Multiple youth","Organization","Club","slingeronbase@gmail.com","Organization inbox","Email","https://slingeronbase.com/tryouts/","","","","2027 tryouts posted","High",checked,"Not contacted","Current club inbox"],
  [38,"Waterford Jr. Wolverines","Both","WI","Waterford","Southeast Wisconsin","7U-14U","Organization","Club","info@jrwolverines.org","Role inbox","Email","https://jrwolverines.org/tryouts-baseball/","","","","2027 baseball and softball tryouts posted","High",checked,"Not contacted","One inbox reaches both sports"],
  [39,"Grafton Travel Baseball","Baseball","WI","Grafton","Southeast Wisconsin","8U-14U","Brian Hagel","Program contact","brian.hagel@graftonlittleleague.com","Role inbox","Email","https://graftonlittleleague.com/grafton-baseball-tryouts/","","","","2027 tryouts posted","High",checked,"Not contacted","Official Little League travel contact"],
  [40,"Stevens Point Youth Baseball","Baseball","WI","Stevens Point","Central Wisconsin","7U-15U","Organization","Program","","Official website","Website contact","https://spyba.sportngin.com/home","","","","2027 registration and evaluations posted","High",checked,"Not contacted","Current central Wisconsin program"],
  [41,"Screaming Eagles Baseball","Baseball","WI","Waterford / Wind Lake","Southeast Wisconsin","Multiple youth","Matt Pinsoneault","Program contact","","Coach contacts on page","Website contact","https://www.screamingeaglesbaseball.com/2026-tryouts","","","","2027 tryouts posted","High",checked,"Not contacted","Official page provides age-level coach routes"],
  [42,"USA Prime State Line / Shockers","Baseball","WI","Genoa City","Southeast Wisconsin","Multiple youth","Bryce","Organization contact","bryce@shockersbaseball.org","Organization email","Email","https://www.shockersbaseball.org/","","","","2027 tryouts active","High",checked,"Not contacted","State-line coverage may reach northern Illinois too"],
  [43,"Wisconsin Dells Baseball Association","Baseball","WI","Wisconsin Dells","South-Central Wisconsin","9U-14U","Organization","Association","","Official website","Website contact","https://www.wdbaseballassociation.com/travel-teams","","","","2026 travel team page active","Medium",checked,"Not contacted","Use site contact route"],
  [44,"Yellow Jackets Softball & Baseball","Both","WI","Johnson Creek","South-Central Wisconsin","6U-18U","Organization","Club","jcyellowjackets2015@gmail.com","Organization inbox","Email","https://www.yellowjacketfastpitch.com/","","","","2026-27 tryouts and 147 athletes noted","High",checked,"Not contacted","One contact reaches both sports"],
  [45,"Wisconsin Twisters Fastpitch","Fastpitch","WI","Raymond","Southeast Wisconsin","10U-18U","Organization","Club","wisconsintwisters@gmail.com","Organization inbox","Email","https://www.wisconsintwistersfastpitch.com/tryouts","","","","2026-27 tryouts and openings posted","High",checked,"Not contacted","Organization inbox preferred over individual board emails"],
  [46,"Wisconsin Rebels Fastpitch","Fastpitch","WI","East-Central Wisconsin","Northeast / East-Central","Multiple youth","Steve Tritt","Program contact","steve.tritt@appletonmarine.com","Director email","Email","https://wisconsinrebelssoftball.org/","","","","2026 tryouts posted; site current","High",checked,"Not contacted","Personal/business email published for team contact"],
  [47,"Point Fastpitch","Fastpitch","WI","Stevens Point","Central Wisconsin","6U-18U","Administrator","Program","pointfastpitch2014@gmail.com","Organization inbox","Email","https://www.pointfastpitch.com/","","","","2026 tournament and program active","High",checked,"Not contacted","Central Wisconsin organization"],
  [48,"Arrowhead Hawks Select Softball","Fastpitch","WI","Hartland / Arrowhead area","Southeast Wisconsin","Multiple youth","Program","Select softball","ladyhawks@arrowheadybs.org","Role inbox","Email","https://www.arrowheadybs.org/page/show/8427206-hawks-select-softball-program","","","","2026 season information posted","High",checked,"Not contacted","Role-based inquiry email"],
  [49,"Force Fastpitch Wisconsin","Fastpitch","WI","Southeast Wisconsin","Southeast Wisconsin","Multiple youth","Organization","Club","","Official contact page","Website contact","https://www.forcefastpitchwi.com/","","","","Current 2026 site","Medium",checked,"Not contacted","Official contact form available"],
  [50,"Ripon Travel Softball","Fastpitch","WI","Ripon","East-Central Wisconsin","8U-16U","Organization","Program","softballripontravel@gmail.com","Organization inbox","Email","https://www.ripontravelsoftball.com/","","","","2026 tournament and teams active","High",checked,"Not contacted","Current program email"],
  [51,"Chippewa Valley Raptors","Fastpitch","WI","Chippewa Valley","Western Wisconsin","Multiple youth","Organization","Club","info@chippewavalleyraptors.com","Role inbox","Email","https://www.chippewavalleyraptors.com/","","","","2026-27 registration active","High",checked,"Not contacted","Western Wisconsin coverage"],
  [52,"Mosinee Youth Girls Softball","Fastpitch","WI","Mosinee","Central Wisconsin","8U-14U","Organization","Program","mosineefastpitch@gmail.com","Organization inbox","Email","https://www.mosineefastpitch.com/program/travel-league/28306","","","","2026 rosters and coaches current","High",checked,"Not contacted","Central Wisconsin program"],
  [53,"Watertown Thunder Fastpitch","Fastpitch","WI","Watertown","South-Central Wisconsin","8U-16U","Organization","Club","wttnthunder@gmail.com","Organization inbox","Email","https://www.watertownsoftball.com/page/show/1681855-2026-tryouts","","","","2027 tryouts posted","High",checked,"Not contacted","Current organization inbox"],
  [54,"Blue Hills Bombers","Fastpitch","WI","Rice Lake","Northwest Wisconsin","8U-14U","Rice Lake Girls Fastpitch","Program","ricelakegirlsfastpitch@gmail.com","Organization inbox","Email","https://www.ricelakesoftball.com/bhbombers","","","","2027 tryouts posted","High",checked,"Not contacted","Northwest Wisconsin coverage"],
  [55,"Northern Ice Fastpitch","Fastpitch","WI","Northern Wisconsin","Northern Wisconsin","8U-18U","Rick Eklund","Program contact","eklund.rick@gmail.com","Director email","Email","https://www.northernicesoftball.com/","","","","2026-27 teams, coaches and openings posted","High",checked,"Not contacted","Multiple team contacts published; director-level listed here"],
  [56,"Wauwatosa Shock","Fastpitch","WI","Wauwatosa / Milwaukee","Southeast Wisconsin","10U-15U","Organization","Club","tosashockfastpitch@gmail.com","Organization inbox","Email","https://www.tosashock.com/","","","","2027 tryouts posted","High",checked,"Not contacted","Milwaukee-area coverage"],
  [57,"Mequon Heat Softball","Fastpitch","WI","Mequon / Thiensville","Southeast Wisconsin","10U-16U","Organization","Program","tmyba12@gmail.com","Organization inbox","Email","https://www.tmyba.org/heatsoftball","","","","2027 tryout page active","High",checked,"Not contacted","Current program inbox"],
  [58,"Two Rivers Warriors Softball","Fastpitch","WI","Two Rivers","Northeast Wisconsin","10U-16U","Softball Committee","Program","softball@traawarriors.com","Role inbox","Email","https://www.traawarriors.com/softball-evals","","","","2027 evaluations posted","High",checked,"Not contacted","Northeast Wisconsin coverage"]
];

const hubs = [
  ["Wisconsin Fastpitch League team directory","WI","Fastpitch","175 registered teams for 2026","director@wisconsinfastpitchleague.com","https://www.wisconsinfastpitchleague.com/team-pages-and-contacts","High-value discovery hub; coach-contact page is password protected, so use public team pages only"],
  ["Wisconsin Fastpitch League","WI","Fastpitch","League contact","director@wisconsinfastpitchleague.com","https://www.wisconsinfastpitchleague.com/","Ask about sponsorship or approved league-wide outreach"],
  ["Wisconsin Fastpitch","WI","Fastpitch","2026 tournament operator","wisconsinfastpitch@charter.net","https://wisconsinfastpitch.com/","Potential tournament/organizer partnership"],
  ["Wisconsin USSSA Fastpitch","WI","Fastpitch","State office / contact form","","https://wifastpitch.usssa.com/contact-us/","Ask about permitted sponsorship or event outreach"],
  ["Wisconsin Baseball Association","WI","Baseball","2026 SE Wisconsin league","wbaleague@outlook.com","https://baseball.exposureevents.com/249330/2026-wba","League contact can reach multiple teams"],
  ["Illinois Fastpitch USSSA","IL","Fastpitch","State directors","perry.clark@usssa.com","https://ilusssa.net/contact-fp","Ask about sponsorship or approved event outreach"],
  ["Illinois Travel Baseball League","IL","Baseball","League contact","webmaster@iltbl.com","https://www.iltbl.com/contact-us.html","Public league contact; verify current participation before campaign"],
  ["Alliance Fastpitch Illinois tryouts","IL","Fastpitch","2026 club/tryout finder","","https://thealliancefastpitch.com/tryouts/?age_division=All&league=All&season=2026&state=IL&type=All","Discovery source for additional clubs"],
  ["Illinois fastpitch Facebook-group guide","IL","Fastpitch","Lists active community groups","","https://sites.google.com/peotoneschools.org/pjhssoftball/travel-general-info","Useful DM/posting communities; follow each group’s promotion rules"],
  ["Chicago Area Travel Baseball Facebook group","IL","Baseball","Regional community group","","https://www.facebook.com/groups/299529534596390/","Request admin approval before promotional posting"],
  ["USA Scout Team Nike Midwest","IL / WI","Baseball","Regional social hub","midwest@usascoutbaseball.com","https://linktr.ee/USAscoutMidwest","Linktree includes Facebook, Instagram and X"],
  ["USSSA Illinois Fastpitch state office","IL","Fastpitch","State organizer","lori.strode@usssa.com","https://ilfastpitch.usssa.com/contact-us/","Southern Illinois state contact listed publicly"]
];

const workbook = Workbook.create();
const overview = workbook.worksheets.add("Overview");
const leadSheet = workbook.worksheets.add("Team Leads");
const hubSheet = workbook.worksheets.add("Discovery Hubs");

for (const sheet of [overview, leadSheet, hubSheet]) sheet.showGridLines = false;

const navy = "#15324A";
const blue = "#247BA0";
const teal = "#2A9D8F";
const paleBlue = "#EAF4F8";
const paleGreen = "#EAF7F3";
const paleYellow = "#FFF4CC";
const paleRed = "#FDECEC";
const gray = "#64748B";
const lightGray = "#E2E8F0";

overview.getRange("A1:H2").merge();
overview.getRange("A1").values = [["PitchMark Outreach Leads — Illinois & Wisconsin"]];
overview.getRange("A1:H2").format = { fill: navy, font: { color: "#FFFFFF", bold: true, size: 20 }, verticalAlignment: "center" };
overview.getRange("A3:H3").merge();
overview.getRange("A3").values = [[`Public baseball and fastpitch contacts checked ${checked}`]];
overview.getRange("A3:H3").format = { fill: paleBlue, font: { color: navy, italic: true } };

overview.getRange("A5:B5").values = [["Lead summary","Count"]];
overview.getRange("A5:B5").format = { fill: blue, font: { color: "#FFFFFF", bold: true } };
overview.getRange("A6:A11").values = [["Total leads"],["Illinois"],["Wisconsin"],["Baseball-only"],["Fastpitch-only"],["Both sports"]];
overview.getRange("B6:B11").formulas = [
  ["=COUNTA('Team Leads'!$B$2:$B$200)"],
  ["=COUNTIF('Team Leads'!$D$2:$D$200,\"IL\")"],
  ["=COUNTIF('Team Leads'!$D$2:$D$200,\"WI\")"],
  ["=COUNTIF('Team Leads'!$C$2:$C$200,\"Baseball\")"],
  ["=COUNTIF('Team Leads'!$C$2:$C$200,\"Fastpitch\")"],
  ["=COUNTIF('Team Leads'!$C$2:$C$200,\"Both\")"]
];
overview.getRange("A6:B11").format.borders = { preset: "inside", style: "thin", color: lightGray };
overview.getRange("B6:B11").format.numberFormat = "0";

overview.getRange("D5:E5").values = [["Outreach readiness","Count"]];
overview.getRange("D5:E5").format = { fill: teal, font: { color: "#FFFFFF", bold: true } };
overview.getRange("D6:D9").values = [["High priority"],["Medium priority"],["Email available"],["Social/contact page only"]];
overview.getRange("E6:E9").formulas = [
  ["=COUNTIF('Team Leads'!$R$2:$R$200,\"High\")"],
  ["=COUNTIF('Team Leads'!$R$2:$R$200,\"Medium\")"],
  ["=B6-E9"],
  ["=COUNTBLANK('Team Leads'!$J$2:$J$59)"]
];
overview.getRange("D6:E9").format.borders = { preset: "inside", style: "thin", color: lightGray };
overview.getRange("E6:E9").format.numberFormat = "0";

overview.getRange("A14:H14").merge();
overview.getRange("A14").values = [["How to use this workbook"]];
overview.getRange("A14:H14").format = { fill: navy, font: { color: "#FFFFFF", bold: true, size: 13 } };
overview.getRange("A15:H19").merge(true);
overview.getRange("A15:A19").values = [
  ["1. Filter Team Leads by State, Sport, Region, Priority, or Best Channel."],
  ["2. Start with organization or role inboxes; personalize messages sent to individual coaches."],
  ["3. Use the public source URL to confirm the contact before sending, especially rows marked Medium."],
  ["4. Record outreach in the Status column to avoid repeat messages."],
  ["5. Discovery Hubs can reach many additional teams or support partnership/sponsorship requests."]
];
overview.getRange("A15:H19").format = { fill: "#F8FAFC", wrapText: true };

overview.getRange("A21:H21").merge();
overview.getRange("A21").values = [["Responsible outreach notes"]];
overview.getRange("A21:H21").format = { fill: "#B45309", font: { color: "#FFFFFF", bold: true, size: 13 } };
overview.getRange("A22:H27").merge(true);
overview.getRange("A22:A27").values = [
  ["• These are public organization/team contacts, not a private USSSA database or password-protected coach list."],
  ["• Keep email targeted and relevant; avoid blasting duplicate contacts across teams in the same organization."],
  ["• For commercial email, use accurate sender information and subject lines, clearly identify the promotion, include a valid postal address and an easy opt-out, and honor opt-outs promptly."],
  ["• FTC guidance says CAN-SPAM covers commercial email, including business-to-business messages."],
  ["• For Facebook/Instagram/X, follow each page or group’s promotional and direct-message rules."],
  ["FTC guidance: https://www.ftc.gov/business-guidance/resources/can-spam-act-compliance-guide-business"]
];
overview.getRange("A22:H27").format = { fill: paleYellow, wrapText: true };

const leadHeaders = ["Lead ID","Organization / Team","Sport","State","City / Area","Region","Age Groups","Contact","Contact Role","Public Email","Email Type","Best Channel","Official / Contact Page","Facebook","Instagram","X","Freshness Evidence","Priority","Checked","Status","Notes"];
leadSheet.getRangeByIndexes(0,0,1,leadHeaders.length).values = [leadHeaders];
leadSheet.getRangeByIndexes(1,0,leads.length,leadHeaders.length).values = leads;
leadSheet.getRangeByIndexes(0,0,leads.length+1,leadHeaders.length).format.wrapText = true;
leadSheet.getRangeByIndexes(0,0,1,leadHeaders.length).format = { fill: navy, font: { color: "#FFFFFF", bold: true }, verticalAlignment: "center" };
const leadTable = leadSheet.tables.add(`A1:U${leads.length+1}`, true, "TeamLeadsTable");
leadTable.style = "TableStyleMedium2";
leadTable.showFilterButton = true;
leadSheet.freezePanes.freezeRows(1);
leadSheet.freezePanes.freezeColumns(2);
leadSheet.getRange(`A2:A${leads.length+1}`).format.numberFormat = "0";
leadSheet.getRange(`S2:S${leads.length+1}`).format.numberFormat = "yyyy-mm-dd";
leadSheet.getRange(`T2:T${leads.length+1}`).dataValidation = { rule: { type: "list", values: ["Not contacted","Queued","Sent","Replied","Not interested","Opted out","Bad contact"] } };
leadSheet.getRange(`R2:R${leads.length+1}`).conditionalFormats.add("containsText", { text: "High", format: { fill: paleGreen, font: { color: "#166534", bold: true } } });
leadSheet.getRange(`R2:R${leads.length+1}`).conditionalFormats.add("containsText", { text: "Medium", format: { fill: paleYellow, font: { color: "#92400E" } } });
leadSheet.getRange(`T2:T${leads.length+1}`).conditionalFormats.add("containsText", { text: "Replied", format: { fill: paleGreen, font: { color: "#166534", bold: true } } });
leadSheet.getRange(`T2:T${leads.length+1}`).conditionalFormats.add("containsText", { text: "Opted out", format: { fill: paleRed, font: { color: "#991B1B", bold: true } } });

const hubHeaders = ["Directory / Community","State","Sport","Current Scope","Public Email","URL","How to Use"];
hubSheet.getRangeByIndexes(0,0,1,hubHeaders.length).values = [hubHeaders];
hubSheet.getRangeByIndexes(1,0,hubs.length,hubHeaders.length).values = hubs;
hubSheet.getRangeByIndexes(0,0,1,hubHeaders.length).format = { fill: navy, font: { color: "#FFFFFF", bold: true } };
hubSheet.getRangeByIndexes(0,0,hubs.length+1,hubHeaders.length).format.wrapText = true;
const hubTable = hubSheet.tables.add(`A1:G${hubs.length+1}`, true, "DiscoveryHubsTable");
hubTable.style = "TableStyleMedium4";
hubTable.showFilterButton = true;
hubSheet.freezePanes.freezeRows(1);

overview.getRange("A1:H27").format.font.name = "Aptos";
leadSheet.getRange(`A1:U${leads.length+1}`).format.font.name = "Aptos";
hubSheet.getRange(`A1:G${hubs.length+1}`).format.font.name = "Aptos";

overview.getRange("A1:H27").format.autofitRows();
overview.getRange("A1:H27").format.columnWidth = 16;
overview.getRange("A1:A27").format.columnWidth = 31;
overview.getRange("D1:D27").format.columnWidth = 27;
overview.getRange("H1:H27").format.columnWidth = 16;

const leadWidths = [9,28,12,8,20,23,15,20,18,31,17,19,43,38,38,30,31,10,12,16,38];
leadWidths.forEach((w,i)=>leadSheet.getRangeByIndexes(0,i,leads.length+1,1).format.columnWidth = w);
leadSheet.getRange(`A1:U${leads.length+1}`).format.autofitRows();
leadSheet.getRange(`A2:U${leads.length+1}`).format.rowHeight = 42;

const hubWidths = [34,10,13,28,31,46,48];
hubWidths.forEach((w,i)=>hubSheet.getRangeByIndexes(0,i,hubs.length+1,1).format.columnWidth = w);
hubSheet.getRange(`A1:G${hubs.length+1}`).format.autofitRows();
hubSheet.getRange(`A2:G${hubs.length+1}`).format.rowHeight = 48;

await fs.mkdir(outputDir, { recursive: true });
const exported = await SpreadsheetFile.exportXlsx(workbook);
await exported.save(outputPath);

const leadInspect = await workbook.inspect({ kind: "table", range: "Team Leads!A1:U8", include: "values,formulas", tableMaxRows: 8, tableMaxCols: 21, maxChars: 12000 });
const summaryInspect = await workbook.inspect({ kind: "table", range: "Overview!A5:E11", include: "values,formulas", tableMaxRows: 10, tableMaxCols: 6, maxChars: 6000 });
const errors = await workbook.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 100 }, summary: "final formula error scan" });
const overviewPng = await workbook.render({ sheetName: "Overview", range: "A1:H27", scale: 1.5, format: "png" });
await fs.writeFile(`${outputDir}/overview_preview.png`, new Uint8Array(await overviewPng.arrayBuffer()));
const leadsPng = await workbook.render({ sheetName: "Team Leads", range: "A1:U12", scale: 1, format: "png" });
await fs.writeFile(`${outputDir}/leads_preview.png`, new Uint8Array(await leadsPng.arrayBuffer()));
const hubsPng = await workbook.render({ sheetName: "Discovery Hubs", range: "A1:G13", scale: 1.2, format: "png" });
await fs.writeFile(`${outputDir}/hubs_preview.png`, new Uint8Array(await hubsPng.arrayBuffer()));

console.log(JSON.stringify({ outputPath, leadInspect: leadInspect.ndjson, summaryInspect: summaryInspect.ndjson, errors: errors.ndjson }, null, 2));
