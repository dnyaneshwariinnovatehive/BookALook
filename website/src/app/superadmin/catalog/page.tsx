'use client';

import { useState, useEffect } from 'react';
import styles from './page.module.css';

interface Template {
  id: string;
  category_id: string;
  name: string;
  estimated_duration_minutes: number;
  is_custom: boolean;
  created_by_salon_id: string | null;
  promoted_to_standard_at: string | null;
  promoted_by: string | null;
  is_active: boolean;
}

interface Category {
  id: string;
  name: string;
  icon_url: string | null;
  is_custom: boolean;
  created_by_salon_id: string | null;
  promoted_to_standard_at: string | null;
  promoted_by: string | null;
  is_active: boolean;
  display_order: number;
  templates: Template[];
}

export default function CatalogPage() {
  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [expandedCategory, setExpandedCategory] = useState<string | null>(null);

  // Modals state
  const [showCatModal, setShowCatModal] = useState(false);
  const [showTplModal, setShowTplModal] = useState(false);
  
  const [editingCategory, setEditingCategory] = useState<Category | null>(null);
  const [editingTemplate, setEditingTemplate] = useState<Template | null>(null);
  const [selectedCatId, setSelectedCatId] = useState<string | null>(null);

  // Form state
  const [catName, setCatName] = useState('');
  const [catIconUrl, setCatIconUrl] = useState('');
  const [catIconFile, setCatIconFile] = useState<File | null>(null);
  const [catIsActive, setCatIsActive] = useState(true);
  const [catDisplayOrder, setCatDisplayOrder] = useState('0');

  const [tplName, setTplName] = useState('');
  const [tplDuration, setTplDuration] = useState('30');
  const [tplIsActive, setTplIsActive] = useState(true);

  useEffect(() => {
    fetchCatalog();
  }, []);

  const fetchCatalog = async () => {
    setLoading(true);
    try {
      const res = await fetch('/api/proxy/superadmin/catalog', {
        headers: {
          'Accept': 'application/json'
        }
      });
      if (res.ok) {
        const data = await res.json();
        setCategories(data.categories);
      } else {
        setError('Failed to load catalog');
      }
    } catch (err) {
      setError('Network error');
    }
    setLoading(false);
  };

  const handleSaveCategory = async (e: React.FormEvent) => {
    e.preventDefault();
    const isEdit = !!editingCategory;
    const url = isEdit 
      ? `/api/proxy/superadmin/catalog/categories/${editingCategory.id}` 
      : '/api/proxy/superadmin/catalog/categories';
    const method = isEdit ? 'PUT' : 'POST';

    try {
      let finalIconUrl = catIconUrl;

      // Upload file first if a new one is selected
      if (catIconFile) {
        const formData = new FormData();
        formData.append('icon', catIconFile);
        
        const uploadRes = await fetch('/api/proxy/superadmin/catalog/categories/upload-icon', {
          method: 'POST',
          body: formData
        });
        
        if (uploadRes.ok) {
          const uploadData = await uploadRes.json();
          finalIconUrl = uploadData.url;
        } else {
          alert('Failed to upload icon');
          return;
        }
      }

      const res = await fetch(url, {
        method,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({ 
          name: catName,
          icon_url: finalIconUrl || null,
          is_active: catIsActive,
          display_order: parseInt(catDisplayOrder) || 0
        })
      });
      if (res.ok) {
        setCatName('');
        setCatIconUrl('');
        setCatIconFile(null);
        setCatIsActive(true);
        setCatDisplayOrder('0');
        setEditingCategory(null);
        setShowCatModal(false);
        fetchCatalog();
      } else {
        alert(`Failed to ${isEdit ? 'edit' : 'add'} category`);
      }
    } catch (err) {
      alert(`Error ${isEdit ? 'editing' : 'adding'} category`);
    }
  };

  const handleDeleteCategory = async (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!confirm('Are you sure you want to delete this category?')) return;
    try {
      const res = await fetch(`/api/proxy/superadmin/catalog/categories/${id}`, {
        method: 'DELETE',
        headers: {
          'Accept': 'application/json'
        }
      });
      if (res.ok) {
        fetchCatalog();
      } else {
        const data = await res.json();
        alert(data.message || 'Failed to delete category');
      }
    } catch (err) {
      alert('Error deleting category');
    }
  };

  const handleSaveTemplate = async (e: React.FormEvent) => {
    e.preventDefault();
    const isEdit = !!editingTemplate;
    const url = isEdit 
      ? `/api/proxy/superadmin/catalog/templates/${editingTemplate.id}` 
      : '/api/proxy/superadmin/catalog/templates';
    const method = isEdit ? 'PUT' : 'POST';

    const bodyData: any = {
      name: tplName,
      estimated_duration_minutes: parseInt(tplDuration),
      is_active: tplIsActive
    };
    if (!isEdit) {
      bodyData.category_id = selectedCatId;
    }

    try {
      const res = await fetch(url, {
        method,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify(bodyData)
      });
      if (res.ok) {
        setTplName('');
        setTplDuration('30');
        setTplIsActive(true);
        setEditingTemplate(null);
        setShowTplModal(false);
        fetchCatalog();
      } else {
        alert(`Failed to ${isEdit ? 'edit' : 'add'} template`);
      }
    } catch (err) {
      alert(`Error ${isEdit ? 'editing' : 'adding'} template`);
    }
  };

  const handleDeleteTemplate = async (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!confirm('Are you sure you want to delete this template?')) return;
    try {
      const res = await fetch(`/api/proxy/superadmin/catalog/templates/${id}`, {
        method: 'DELETE',
        headers: {
          'Accept': 'application/json'
        }
      });
      if (res.ok) {
        fetchCatalog();
      } else {
        alert('Failed to delete template');
      }
    } catch (err) {
      alert('Error deleting template');
    }
  };

  const handlePromoteCategory = async (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!confirm('Are you sure you want to promote this category? It will become visible to all salons.')) return;
    try {
      const res = await fetch(`/api/proxy/superadmin/catalog/categories/${id}/promote`, {
        method: 'PUT',
        headers: {
          'Accept': 'application/json'
        }
      });
      if (res.ok) {
        fetchCatalog();
      }
    } catch (err) {
      alert('Error promoting category');
    }
  };

  const handlePromoteTemplate = async (id: string) => {
    if (!confirm('Are you sure you want to promote this template? It will become visible to all salons.')) return;
    try {
      const res = await fetch(`/api/proxy/superadmin/catalog/templates/${id}/promote`, {
        method: 'PUT',
        headers: {
          'Accept': 'application/json'
        }
      });
      if (res.ok) {
        fetchCatalog();
      }
    } catch (err) {
      alert('Error promoting template');
    }
  };

  const openAddCategory = () => {
    setEditingCategory(null);
    setCatName('');
    setCatIconUrl('');
    setCatIconFile(null);
    setCatIsActive(true);
    setCatDisplayOrder('0');
    setShowCatModal(true);
  };

  const openEditCategory = (cat: Category, e: React.MouseEvent) => {
    e.stopPropagation();
    setEditingCategory(cat);
    setCatName(cat.name);
    setCatIconUrl(cat.icon_url || '');
    setCatIconFile(null);
    setCatIsActive(cat.is_active);
    setCatDisplayOrder(cat.display_order.toString());
    setShowCatModal(true);
  };

  const openAddTemplate = (catId: string) => {
    setSelectedCatId(catId);
    setEditingTemplate(null);
    setTplName('');
    setTplDuration('30');
    setTplIsActive(true);
    setShowTplModal(true);
  };

  const openEditTemplate = (tpl: Template, e: React.MouseEvent) => {
    e.stopPropagation();
    setEditingTemplate(tpl);
    setTplName(tpl.name);
    setTplDuration(tpl.estimated_duration_minutes.toString());
    setTplIsActive(tpl.is_active);
    setShowTplModal(true);
  };

  if (loading) return <div>Loading Catalog...</div>;
  if (error) return <div>Error: {error}</div>;

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h1 className={styles.title}>Service Category & Master Catalog</h1>
        <button className={styles.addButton} onClick={openAddCategory}>
          + Add Standard Category
        </button>
      </div>

      <div className={styles.catalogList}>
        {categories.map(cat => (
          <div key={cat.id} className={styles.categoryCard}>
            <div 
              className={styles.categoryHeader} 
              onClick={() => setExpandedCategory(expandedCategory === cat.id ? null : cat.id)}
            >
              <div className={styles.categoryInfo}>
                <div className={styles.iconSquare}>
                  {cat.icon_url ? (
                    <img src={cat.icon_url} alt={cat.name} className={styles.catImage} />
                  ) : (
                    <div className={styles.catImagePlaceholder}>
                      {cat.name.charAt(0).toUpperCase()}
                    </div>
                  )}
                </div>
                <div style={{ display: 'flex', flexDirection: 'column' }}>
                  <span className={styles.categoryName}>{cat.name}</span>
                  <div style={{ display: 'flex', gap: '8px', marginTop: '4px', alignItems: 'center' }}>
                    <span className={`${styles.badge} ${cat.is_custom ? styles.badgeCustom : styles.badgeStandard}`}>
                      {cat.is_custom ? 'Custom' : 'Standard'}
                    </span>
                    {!cat.is_active && (
                      <span className={`${styles.badge} ${styles.badgeInactive}`}>Inactive</span>
                    )}
                  </div>
                </div>
                {cat.is_custom && (
                  <button className={styles.promoteBtn} onClick={(e) => handlePromoteCategory(cat.id, e)}>
                    Promote
                  </button>
                )}
              </div>
              <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                <button className={styles.editBtn} onClick={(e) => openEditCategory(cat, e)}>Edit</button>
                <button className={styles.deleteBtn} onClick={(e) => handleDeleteCategory(cat.id, e)}>Delete</button>
                <span style={{ marginLeft: '8px', color: '#9CA3AF' }}>
                  {expandedCategory === cat.id ? '▼' : '▶'}
                </span>
              </div>
            </div>

            {expandedCategory === cat.id && (
              <div className={styles.templatesList}>
                <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: '8px' }}>
                  <button 
                    className={styles.addButton} 
                    style={{ fontSize: '12px', padding: '6px 12px' }}
                    onClick={() => openAddTemplate(cat.id)}
                  >
                    + Add Template
                  </button>
                </div>
                
                {cat.templates.length === 0 ? (
                  <div style={{ textAlign: 'center', color: '#6B7280', padding: '16px' }}>No templates yet</div>
                ) : (
                  cat.templates.map(tpl => (
                    <div key={tpl.id} className={styles.templateItem}>
                      <div className={styles.templateInfo}>
                        <span className={styles.templateName}>{tpl.name}</span>
                        <span className={styles.templateDuration}>{tpl.estimated_duration_minutes} mins</span>
                        <span className={`${styles.badge} ${tpl.is_custom ? styles.badgeCustom : styles.badgeStandard}`}>
                          {tpl.is_custom ? 'Custom' : 'Standard'}
                        </span>
                      </div>
                      <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                        {tpl.is_custom && (
                          <button className={styles.promoteBtn} onClick={() => handlePromoteTemplate(tpl.id)}>
                            Promote
                          </button>
                        )}
                        <button className={styles.editBtn} onClick={(e) => openEditTemplate(tpl, e)}>Edit</button>
                        <button className={styles.deleteBtn} onClick={(e) => handleDeleteTemplate(tpl.id, e)}>Delete</button>
                      </div>
                    </div>
                  ))
                )}
              </div>
            )}
          </div>
        ))}
      </div>

      {/* Add/Edit Category Modal */}
      {showCatModal && (
        <div className={styles.modalOverlay}>
          <div className={styles.modal}>
            <h2 className={styles.modalTitle}>{editingCategory ? 'Edit Category' : 'Add Standard Category'}</h2>
            <form onSubmit={handleSaveCategory}>
              <div className={styles.formGroup}>
                <label>Category Name</label>
                <input 
                  type="text" 
                  value={catName} 
                  onChange={(e) => setCatName(e.target.value)}
                  placeholder="e.g. Hair Care"
                  required
                />
              </div>
              <div className={styles.formGroup}>
                <label>Category Icon (optional)</label>
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  {catIconUrl && !catIconFile && (
                    <img src={catIconUrl} alt="Icon preview" style={{ width: 40, height: 40, objectFit: 'contain', border: '1px solid #ccc', borderRadius: 4 }} />
                  )}
                  <input 
                    type="file" 
                    accept="image/*"
                    onChange={(e) => {
                      if (e.target.files && e.target.files.length > 0) {
                        setCatIconFile(e.target.files[0]);
                      }
                    }}
                    style={{ border: 'none', padding: 0 }}
                  />
                </div>
              </div>
              <div className={styles.formGroup}>
                <label>Display Order</label>
                <input 
                  type="number" 
                  value={catDisplayOrder} 
                  onChange={(e) => setCatDisplayOrder(e.target.value)}
                />
              </div>
              <label className={styles.checkboxGroup}>
                <input 
                  type="checkbox" 
                  checked={catIsActive} 
                  onChange={(e) => setCatIsActive(e.target.checked)}
                />
                <span>Is Active (Visible to users)</span>
              </label>
              <div className={styles.modalActions}>
                <button type="button" className={styles.cancelBtn} onClick={() => {
                  setShowCatModal(false);
                  setEditingCategory(null);
                }}>Cancel</button>
                <button type="submit" className={styles.saveBtn}>Save Category</button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Add/Edit Template Modal */}
      {showTplModal && (
        <div className={styles.modalOverlay}>
          <div className={styles.modal}>
            <h2 className={styles.modalTitle}>{editingTemplate ? 'Edit Template' : 'Add Standard Template'}</h2>
            <form onSubmit={handleSaveTemplate}>
              <div className={styles.formGroup}>
                <label>Service Name</label>
                <input 
                  type="text" 
                  value={tplName} 
                  onChange={(e) => setTplName(e.target.value)}
                  placeholder="e.g. Men's Haircut"
                  required
                />
              </div>
              <div className={styles.formGroup}>
                <label>Duration (minutes)</label>
                <input 
                  type="number" 
                  value={tplDuration} 
                  onChange={(e) => setTplDuration(e.target.value)}
                  min="30"
                  step="30"
                  required
                />
              </div>
              <label className={styles.checkboxGroup}>
                <input 
                  type="checkbox" 
                  checked={tplIsActive} 
                  onChange={(e) => setTplIsActive(e.target.checked)}
                />
                <span>Is Active (Visible to users)</span>
              </label>
              <div className={styles.modalActions}>
                <button type="button" className={styles.cancelBtn} onClick={() => {
                  setShowTplModal(false);
                  setEditingTemplate(null);
                }}>Cancel</button>
                <button type="submit" className={styles.saveBtn}>Save Template</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
