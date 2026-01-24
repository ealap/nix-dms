.pragma library

const Weights = {
    exactMatch: 10000,
    prefixMatch: 5000,
    wordBoundary: 1000,
    substring: 500,
    fuzzy: 100,
    frecency: 2000,
    typeBonus: {
        app: 1000,
        plugin: 900,
        file: 800,
        action: 600
    }
}

function tokenize(text) {
    return text.toLowerCase().trim().split(/[\s\-_]+/).filter(function (w) { return w.length > 0 })
}

function hasWordBoundaryMatch(text, query) {
    var textWords = tokenize(text)
    var queryWords = tokenize(query)

    if (queryWords.length === 0) return false
    if (queryWords.length > textWords.length) return false

    for (var i = 0; i <= textWords.length - queryWords.length; i++) {
        var allMatch = true
        for (var j = 0; j < queryWords.length; j++) {
            if (!textWords[i + j].startsWith(queryWords[j])) {
                allMatch = false
                break
            }
        }
        if (allMatch) return true
    }
    return false
}

function levenshteinDistance(s1, s2) {
    var len1 = s1.length
    var len2 = s2.length
    var matrix = []

    for (var i = 0; i <= len1; i++) {
        matrix[i] = [i]
    }
    for (var j = 0; j <= len2; j++) {
        matrix[0][j] = j
    }

    for (var i = 1; i <= len1; i++) {
        for (var j = 1; j <= len2; j++) {
            var cost = s1[i - 1] === s2[j - 1] ? 0 : 1
            matrix[i][j] = Math.min(
                matrix[i - 1][j] + 1,
                matrix[i][j - 1] + 1,
                matrix[i - 1][j - 1] + cost
            )
        }
    }
    return matrix[len1][len2]
}

function fuzzyScore(text, query) {
    var maxDistance = query.length === 3 ? 1 : query.length <= 6 ? 2 : 3
    var bestScore = 0

    if (Math.abs(text.length - query.length) <= maxDistance) {
        var distance = levenshteinDistance(text, query)
        if (distance <= maxDistance) {
            var maxLen = Math.max(text.length, query.length)
            bestScore = 1 - (distance / maxLen)
        }
    }

    var words = tokenize(text)
    for (var i = 0; i < words.length && bestScore < 0.8; i++) {
        if (Math.abs(words[i].length - query.length) > maxDistance) continue
        var wordDistance = levenshteinDistance(words[i], query)
        if (wordDistance <= maxDistance) {
            var wordMaxLen = Math.max(words[i].length, query.length)
            var score = 1 - (wordDistance / wordMaxLen)
            bestScore = Math.max(bestScore, score)
        }
    }

    return bestScore
}

function getTimeBucketWeight(daysSinceUsed) {
    for (var i = 0; i < TimeBuckets.length; i++) {
        if (daysSinceUsed <= TimeBuckets[i].maxDays) {
            return TimeBuckets[i].weight
        }
    }
    return 10
}

function calculateTextScore(name, query) {
    if (name === query) return Weights.exactMatch
    if (name.startsWith(query)) return Weights.prefixMatch
    if (name.includes(query)) return Weights.substring
    if (hasWordBoundaryMatch(name, query)) return Weights.wordBoundary

    if (query.length >= 3) {
        var fs = fuzzyScore(name, query)
        if (fs > 0) return fs * Weights.fuzzy
    }

    return 0
}

function score(item, query, frecencyData) {
    var typeBonus = Weights.typeBonus[item.type] || 0

    if (!query || query.length === 0) {
        var usageCount = frecencyData ? frecencyData.usageCount : 0
        return typeBonus + (usageCount * 100)
    }

    var name = (item.name || "").toLowerCase()
    var q = query.toLowerCase()

    var textScore = calculateTextScore(name, q)

    if (textScore === 0 && item.subtitle) {
        var subtitleScore = calculateTextScore(item.subtitle.toLowerCase(), q)
        textScore = subtitleScore * 0.5
    }

    if (textScore === 0 && item.keywords) {
        for (var i = 0; i < item.keywords.length; i++) {
            var keywordScore = calculateTextScore(item.keywords[i].toLowerCase(), q)
            if (keywordScore > 0) {
                textScore = keywordScore * 0.3
                break
            }
        }
    }

    if (textScore === 0) return 0

    var usageBonus = frecencyData ? Math.min(frecencyData.usageCount * 10, Weights.frecency) : 0

    return textScore + usageBonus + typeBonus
}

function scoreItems(items, query, getFrecencyFn) {
    var scored = []

    for (var i = 0; i < items.length; i++) {
        var item = items[i]
        var frecencyData = getFrecencyFn ? getFrecencyFn(item) : null
        var itemScore = score(item, query, frecencyData)

        if (itemScore > 0 || !query || query.length === 0) {
            scored.push({
                item: item,
                score: itemScore
            })
        }
    }

    scored.sort(function (a, b) {
        return b.score - a.score
    })

    return scored
}

function groupBySection(scoredItems, sectionOrder, sortAlphabetically, maxPerSection) {
    var sections = {}
    var result = []
    var limit = maxPerSection || 50

    for (var i = 0; i < sectionOrder.length; i++) {
        var sectionId = sectionOrder[i].id
        sections[sectionId] = {
            id: sectionId,
            title: sectionOrder[i].title,
            icon: sectionOrder[i].icon,
            priority: sectionOrder[i].priority,
            items: [],
            collapsed: false
        }
    }

    for (var i = 0; i < scoredItems.length; i++) {
        var scoredItem = scoredItems[i]
        var item = scoredItem.item
        var sectionId = item.section || "apps"

        if (sections[sectionId] && sections[sectionId].items.length < limit) {
            sections[sectionId].items.push(item)
        } else if (sections["apps"] && sections["apps"].items.length < limit) {
            sections["apps"].items.push(item)
        }
    }

    for (var i = 0; i < sectionOrder.length; i++) {
        var section = sections[sectionOrder[i].id]
        if (section && section.items.length > 0) {
            if (sortAlphabetically && section.id === "apps") {
                section.items.sort(function (a, b) {
                    return (a.name || "").localeCompare(b.name || "")
                })
            }
            result.push(section)
        }
    }

    return result
}

function flattenSections(sections) {
    var flat = []

    for (var i = 0; i < sections.length; i++) {
        var section = sections[i]

        flat.push({
            isHeader: true,
            section: section,
            sectionId: section.id,
            sectionIndex: i
        })

        if (!section.collapsed) {
            for (var j = 0; j < section.items.length; j++) {
                flat.push({
                    isHeader: false,
                    item: section.items[j],
                    sectionId: section.id,
                    sectionIndex: i,
                    indexInSection: j
                })
            }
        }
    }

    return flat
}
