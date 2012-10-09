#node
pathUtil = require 'path'
fs = require 'fs'
#argparse
argparse = require 'argparse'
#analyse
cson = require 'cson'
xml2js = require 'xml2js'
yaml = require 'js-yaml'
exec = require('child_process').exec


class TwoDimStruc

	constructor: ->
		@values = {}
		@x = {}
		@y = {}
		@maxX = 0
		@maxY = 0

	addElement : (value, x, y) =>
		id = x+":"+y
		@values[id] = value
		@x[id] = x
		@y[id] = y
		if @maxX < x
			@maxX = x
		if @maxY < y
			@maxY = y

	getElement : (x, y) =>
		if @values[x+":"+y]?
			@values[x+":"+y]
		else
			undefined

	getRow : (x) =>
		result = {}
		max = 0 
		ids = (id for id, value of @x when value is x)
		for id in ids
			indice = parseInt(id.split(":")[1], 10)
			result[indice] = @values[id]
			if (max < indice)
				max = indice
		{content : result, max : max }

	getColumn : (y) =>
		result = {}
		max = 0
		ids = (id for id, value of @y when value is y)
		for id in ids
			indice = parseInt(id.split(":")[0], 10)
			result[indice] = @values[id]
			if (max < indice)
				max = indice
		{content : result, max : max }

	getRows : () =>
		result = {}
		num = 0
		while num <= @maxX
			result[num] = @getRow(num)
			num += 1
		result

	getColumns : () =>
		result = {}
		num = 0
		while num <= @maxY
			result[num] = @getRow(num)
			num += 1
		result

	convertToCSV : (separator, escape) =>
		separator ?= ";"
		escape ?= ""
		csv = ""
		i = 0
		while i <= @maxX
			currentRow = @getRow(i)
			j = 0
			while j <= @maxY
				currentValue = currentRow.content[j] ? ""
				if j is 0 
					csv += "#{currentValue}"
				else
					csv += "#{separator}#{currentValue}"
				j += 1
			csv += "\n"
			i += 1
		csv

usableFormat =
	json : JSON.parse
	yaml : yaml.load
	cson : cson.parseSync
	#xml : "parser"

attrSchema = 
	id: 1
	parent: 2
	label: 3
	intitle: 4
	inabstract: 5
	type: 6
	order: 7
	visibility: 8
	need: 9
	link: 10
	phpfile: 11
	phpfunc: 12
	elink: 13
	constraint: 14
	options: 15
	commentaires: 16

notAttrSchema = ["modattr", "children","attr", "default"]

famSchema =
	father :
		column : 1
		row : 1
	title :
		column : 2
		row : 1
	id :
		column : 3
		row : 1
	classname :
		column : 4
		row : 1
	logicalname :
		column : 5
		row : 1

firstLineSchema =
	"//" : 0
	Father : 1
	Title : 2
	Id : 3
	Classe : 4
	"Logical Name" : 5

autonumRules =
	'tab' : 1000
	'frame' : 100

defaultValuesRules =
	'global' : 
		visibility : "W"
		intitle : "N"
		inabstract : "N"
	'htmltext' :
		options : 'toolbar=Basic|toolbarexpand=n'
	'enum' :
		options : 'bmenu=no|eunset=yes|system=yes'
	'array' :
		options : 'vlabel=up'
	'longtext' :
		options : 'editheight=4em'


populateDefaultValues = (attr) ->
	if attr.type?
		for type, defaultValues of defaultValuesRules
			if attr.type is type or type is "global"
				for key, value of defaultValues
					attr[key] ?= value
	attr

initFirstLine = (twoDim) ->
	for element, y of firstLineSchema
		twoDim.addElement(element, 0, y)

generateFirstPart = (twoDim, elements) -> 
	for key, element of elements when not(key in ['attributes', 'parameters'])
		lowerKey = key.toLowerCase()
		if famSchema[lowerKey]?
			twoDim.addElement(element, famSchema[lowerKey].row, famSchema[lowerKey].column)
		else
			if twoDim.maxX < 2
				line = 2
			else
				line = twoDim.maxX + 1
			twoDim.addElement(key, line, 0)
			twoDim.addElement(element, line, 1)

firstAttributesLine = (twoDim) ->
	line = twoDim.maxX + 1
	twoDim.addElement("//", line, 0)
	for key, column of attrSchema
		twoDim.addElement(key, line, column)

computeOrder = (type, lastOrder) ->
	lastOrder ?= 0
	value = lastOrder + (autonumRules[type] ? 10)
	value

generateAttributes = (twoDim, attributes, myParent, param) ->
	for attrId, attrContent of attributes
		modAttr = false
		line = twoDim.maxX + 1
		twoDim.addElement(attrId, line, 1)
		currentOrder = undefined
		currentParent = myParent
		currentType = undefined
		if args.computeDefaultValue
			attrContent = populateDefaultValues(attrContent)
		for key, currentContent of attrContent
			key = key.toLowerCase()
			if attrSchema[key]?
				if key is "parent"
					currentParent = currentContent
				if key is "order"
					currentOrder = currentContent
					unless isNaN(parseInt(currentOrder, 10))
						twoDim.currentOrder = parseInt(currentOrder, 10)
				if key is "type"
					currentType = currentContent
				twoDim.addElement(currentContent, line, attrSchema[key])
			else
				if key not in notAttrSchema
					throw "Unknown "+key
			if key is "modattr"
				modAttr = true
		if param
			twoDim.addElement("PARAM", line, 0)
			if args.autonum and not(currentOrder?)
					twoDim.currentOrder = computeOrder(currentType, twoDim.currentOrder)
					twoDim.addElement(twoDim.currentOrder, line, attrSchema["order"])
		else
			if modAttr
				twoDim.addElement("MODATTR", line, 0)
			else
				twoDim.addElement("ATTR", line, 0)
				unless currentType?
					throw "Attr "+attrId+" needs a type"
				if args.autonum and not(currentOrder?)
					twoDim.currentOrder = computeOrder(currentType, twoDim.currentOrder)
					twoDim.addElement(twoDim.currentOrder, line, attrSchema["order"])
		if currentParent?
			twoDim.addElement(currentParent, line, 2)
		if attrContent.default?
			twoDim.addElement("DEFAULT", line+1, 0)
			twoDim.addElement(attrId, line+1, 1)
			twoDim.addElement(attrContent.default, line+1, 2)
		if attrContent.children?
			generateAttributes(twoDim, attrContent.children, attrId, param)

analyse = (elements) ->
	if elements
		twoDim = new TwoDimStruc()
		initFirstLine(twoDim)
		twoDim.addElement("BEGIN", 1, 0)
		generateFirstPart twoDim, elements
		if elements["attributes"]?
			firstAttributesLine twoDim
			generateAttributes twoDim, elements["attributes"]
		if elements["parameters"]?
			firstAttributesLine twoDim
			generateAttributes(twoDim, elements["parameters"], undefined, true)
		twoDim.addElement("END", twoDim.maxX+1, 0)
		twoDim

parse = (fileName, fileContent, callBack) ->
	if fileContent
		ext = fileName.substr(fileName.lastIndexOf('.')+1).toLowerCase()
		if usableFormat[ext]?
			if ext isnt "xml"
				callBack(usableFormat[ext](fileContent))
			else
				parser = new xml2js.Parser()
				parser.parseString(fileContent, 
					(err, result) ->
						if err
							throw err
						callBack(result)
					)
		else
			throw "Unknown type of file "+ext
	else
		throw "The file "+fileName+" is empty"

canBeParsed = (fileName) ->
	ext = fileName.substr(fileName.lastIndexOf('.')+1).toLowerCase()
	return usableFormat[ext]?

analyseFile = (inputFileName, outputFileName) ->
	(err, content) ->
		parse(inputFileName, content, 
			(elements) ->
				twoDim = analyse(elements)
				fs.writeFile(outputFileName, 
					twoDim.convertToCSV(), 
					write = (err) -> 
						if err 
							throw err
						else
							console.log(outputFileName+" is saved");
					)
			)

analyseAPath = (path) ->
	fs.exists(path, 
			checkIfExist = (exist) ->
				if exist
					fs.stat(path, 
						(err, stats) ->
							if err 
								throw err
							if stats.isFile() && canBeParsed(path)
								console.log("Analyse "+path)
								outputFileName = getCSVFileName(path)
								fs.readFile(path, "utf8", analyseFile(path, outputFileName))
							else
								fs.readdir(path,
									(err, fileNames) ->
										if fileNames
											for fileName in fileNames
												analyseAPath(pathUtil.join(path,fileName))
									)
						)
				else
					console.log path+" notExist"
				)

getCSVFileName = (inputFileName) ->
	baseName = inputFileName.substr(0, inputFileName.lastIndexOf('.'))
	baseName += ".csv"
	baseName

parser = new argparse.ArgumentParser({
	version: '0.0.1',
	addHelp:true,
	description: 'convert a modern fam def to old style'
})

parser.addArgument(
	[ 'input' ],
	{
		help: 'input file (json, cson, xml or YAML) or input dir (if --watch used)'
	}
)

parser.addArgument(
	[ '-w', '--watch' ],
	{
		help: 'rebuild the file if source modified',
		defaultValue : false
	}
)

parser.addArgument(
	[ '--autonum' ],
	{
		help: 'compute position number',
		defaultValue : true
	}
)

parser.addArgument(
	[ '--computeDefaultValue' ],
	{
		help: 'add default value',
		defaultValue : true
	}
)

args = parser.parseArgs()

if args.input
	if args.watch
		if fs.statSync(args.input).isDirectory()
			dir = args.input
		else
			dir = pathUtil.dirname(args.input)
		console.log "Start watching ", dir
		fs.watch(args.input,
			onChange = (event, fileName) ->
				if fileName and canBeParsed(fileName)
					analyseAPath(pathUtil.join(dir, fileName))
			)
	analyseAPath(args.input)
else
	parser.printHelp();

process.on 'uncaughtException', (err) ->
	msg = 'Caught exception : ' + err
	msg = msg.replace(/["]/mgi, '\\"').replace(/[']/mgi, "\\'").replace(/[\n]/mgi, ' ')
	command = 'notify-send --hint=int:transient:1 "Generate Family Error" "'+msg+'"'
	exec(command)
	console.log msg