import itertools
from re import sub

def produce_sents(grammar):
    tree = {}
    for l1_tag in grammar['S'].split():
        tree[l1_tag] = []
        #   1    
        for l2_tag in grammar[l1_tag]:
            if ' ' in l2_tag: 
                subtree = []
                for part in l2_tag.split():
                    #   2    
                    subtree.append(grammar[part])
                # print(subtree)
                tree[l1_tag].extend([" ".join(part) for part in 
                                    list(itertools.product(*subtree))])
                
            else:
                #   3    
                words = grammar[l2_tag]
                tree[l1_tag].extend(words)
    #   4    
    print(list(tree.values()))
    components = itertools.product(*tree.values())
    return [" ".join(part) for part in list(components)]

def validate(sentences, sentence):
    #   5 
    if sentence in sentences:   
        return True
    return False
print(validate(produce_sents({'S':'NP VP', 'VP':['IV', 'TV PN'], 'IV':['runs','sits'], 'NP':['N','D N'], 'PN': ['john', 'mary'],'N':['squirrel', 'cat','mouse', 'dog', 'tree'], 'TV':['chases', 'catches', 'tells', 'sees','eats'],'D':['the','a'] }), "a cat sits"))


# print({'a':[((1,2),(2,3)), ((3,4),(4,5))]}.items()[0][0
# print(tuple({'a':[(1,2),(3,4)]}.items())[0][1][0])

# {1:{'COS10001'}}[int('1 2'.split()[0])]