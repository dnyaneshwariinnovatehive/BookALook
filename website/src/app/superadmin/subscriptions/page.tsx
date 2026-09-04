'use client';

import { useState, useEffect } from 'react';
import styles from './page.module.css';

export default function SubscriptionsPage() {
  const [plans, setPlans] = useState<any[]>([]);
  const [salons, setSalons] = useState<any[]>([]);
  const [subscriptionRequests, setSubscriptionRequests] = useState<any[]>([]);
  const [viewingScreenshot, setViewingScreenshot] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  // Form State for Creating/Editing Plans
  const [isPlanModalOpen, setIsPlanModalOpen] = useState(false);
  const [editingPlanId, setEditingPlanId] = useState<string | null>(null);
  const [planFormData, setPlanFormData] = useState({
    name: '',
    price: '',
    whatsapp_campaign_limit: '',
    has_customer_segmentation: false,
    has_service_based_targeting: false,
    has_high_value_targeting: false,
    has_advanced_insights: false,
    has_upsell_recommendations: 'none',
    has_cross_sell_recommendations: 'none',
    has_priority_visibility: false,
    is_active: true,
    validity_days: '30',
  });

  // Form State for Assigning Salon Plan
  const [assigningSalon, setAssigningSalon] = useState<any>(null);
  const [billingType, setBillingType] = useState('flat');
  const [commissionPercentage, setCommissionPercentage] = useState('');
  const [selectedPlanId, setSelectedPlanId] = useState('');

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      const res = await fetch('/api/superadmin/subscriptions/plans');
      const data = await res.json();
      if (data.success) {
        setPlans(data.plans);
        setSalons(data.salons);
        if (data.plans.length > 0) {
          setSelectedPlanId(data.plans[0].id);
        }
      }

      const reqRes = await fetch('/api/superadmin/subscription-requests');
      const reqData = await reqRes.json();
      if (reqData.success) {
        setSubscriptionRequests(reqData.requests);
      }
    } catch (e) {
      console.error(e);
    } finally {
      setIsLoading(false);
    }
  };

  const openCreateModal = () => {
    setEditingPlanId(null);
    setPlanFormData({
      name: '',
      price: '',
      whatsapp_campaign_limit: '',
      has_customer_segmentation: false,
      has_service_based_targeting: false,
      has_high_value_targeting: false,
      has_advanced_insights: false,
      has_upsell_recommendations: 'none',
      has_cross_sell_recommendations: 'none',
      has_priority_visibility: false,
      is_active: true,
      validity_days: '30',
    });
    setIsPlanModalOpen(true);
  };

  const openEditModal = (plan: any) => {
    setEditingPlanId(plan.id);
    setPlanFormData({
      name: plan.name,
      price: plan.price.toString(),
      whatsapp_campaign_limit: plan.whatsapp_campaign_limit.toString(),
      has_customer_segmentation: plan.has_customer_segmentation,
      has_service_based_targeting: plan.has_service_based_targeting,
      has_high_value_targeting: plan.has_high_value_targeting,
      has_advanced_insights: plan.has_advanced_insights,
      has_upsell_recommendations: plan.has_upsell_recommendations,
      has_cross_sell_recommendations: plan.has_cross_sell_recommendations,
      has_priority_visibility: plan.has_priority_visibility,
      is_active: plan.is_active,
      validity_days: plan.validity_days.toString(),
    });
    setIsPlanModalOpen(true);
  };

  const handleSavePlan = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const url = editingPlanId 
        ? `/api/superadmin/subscriptions/plans/${editingPlanId}`
        : `/api/superadmin/subscriptions/plans`;
      
      const method = editingPlanId ? 'PUT' : 'POST';

      const res = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(planFormData)
      });
      if (res.ok) {
        setIsPlanModalOpen(false);
        fetchData();
        alert(`Plan ${editingPlanId ? 'updated' : 'created'} successfully`);
      }
    } catch (e) {
      console.error(e);
    }
  };

  const handleDeletePlan = async (id: string) => {
    if (!confirm('Are you sure you want to delete this plan? Salons subscribed to it must be unassigned first.')) return;
    try {
      const res = await fetch(`/api/superadmin/subscriptions/plans/${id}`, {
        method: 'DELETE',
      });
      if (res.ok) {
        fetchData();
        alert('Plan deleted successfully');
      } else {
        const err = await res.json();
        alert(err.message || 'Failed to delete plan.');
      }
    } catch (e) {
      console.error(e);
    }
  };

  const handleAssignPlan = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!assigningSalon) return;
    try {
      const res = await fetch(`/api/superadmin/salons/${assigningSalon.id}/subscription`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          plan_id: selectedPlanId,
          billing_type: billingType,
          commission_percentage: commissionPercentage ? parseFloat(commissionPercentage) : null
        })
      });
      if (res.ok) {
        setAssigningSalon(null);
        fetchData();
        alert('Subscription assigned successfully');
      }
    } catch (e) {
      console.error(e);
    }
  };

  if (isLoading) return <div>Loading...</div>;

  return (
    <div className={styles.container}>
      <h1 className={styles.title}>Subscription Plan Management</h1>
      
      {subscriptionRequests.length > 0 && (
        <div className={styles.section} style={{ border: '2px solid #eab308', padding: '24px', borderRadius: '8px', marginBottom: '32px' }}>
          <h2 style={{ color: '#eab308', marginTop: 0 }}>Pending Payment Approvals</h2>
          <table className={styles.table}>
            <thead>
              <tr>
                <th>Salon Name</th>
                <th>Requested Plan</th>
                <th>Billing Type</th>
                <th>Date</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {subscriptionRequests.map(req => (
                <tr key={req.id}>
                  <td>{req.salon?.name}</td>
                  <td>{req.plan?.name || 'N/A'}</td>
                  <td>{req.billing_type === 'commission' ? 'Commission Based' : 'Subscription Based'}</td>
                  <td>{new Date(req.created_at).toLocaleDateString()}</td>
                  <td>
                    <button 
                      className={styles.button} 
                      style={{ marginRight: '8px', background: '#3b82f6' }}
                      onClick={() => setViewingScreenshot(req.screenshot_url)}
                    >
                      View Screenshot
                    </button>
                    <button 
                      className={styles.button} 
                      style={{ background: '#22c55e' }}
                      onClick={() => {
                        setAssigningSalon(req.salon);
                        setSelectedPlanId(req.plan?.id || plans[0]?.id);
                        setBillingType(req.billing_type);
                      }}
                    >
                      Approve & Assign
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {viewingScreenshot && (
        <div className={styles.modalOverlay} onClick={() => setViewingScreenshot(null)}>
          <div className={styles.modalContent} style={{ maxWidth: '800px', textAlign: 'center' }} onClick={e => e.stopPropagation()}>
            <h3>Payment Screenshot</h3>
            <img src={viewingScreenshot} alt="Payment Screenshot" style={{ maxWidth: '100%', maxHeight: '70vh', objectFit: 'contain', margin: '16px 0' }} />
            <div className={styles.formActions}>
              <button type="button" onClick={() => setViewingScreenshot(null)} className={styles.cancelButton}>Close</button>
            </div>
          </div>
        </div>
      )}

      <div className={styles.section}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h2>Master Plans</h2>
          <button className={styles.button} onClick={openCreateModal}>+ Create New Plan</button>
        </div>
        <div className={styles.grid}>
          {plans.map(plan => (
            <div key={plan.id} className={styles.card}>
              <h3>{plan.name} Plan</h3>
              <p><strong>Price:</strong> ₹{plan.price}</p>
              <p><strong>Validity:</strong> {plan.validity_days} Days</p>
              <p><strong>WhatsApp Limit:</strong> {plan.whatsapp_campaign_limit}</p>
              <p><strong>Status:</strong> {plan.is_active ? 'Active' : 'Inactive'}</p>
              
              <div style={{ display: 'flex', gap: '8px', marginTop: '16px' }}>
                <button 
                  className={styles.button}
                  onClick={() => openEditModal(plan)}
                >
                  Edit
                </button>
                <button 
                  className={styles.cancelButton}
                  style={{ marginTop: '16px', padding: '8px 16px' }}
                  onClick={() => handleDeletePlan(plan.id)}
                >
                  Delete
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>

      {isPlanModalOpen && (
        <div className={styles.modalOverlay}>
          <div className={styles.modalContent} style={{ maxWidth: '600px', maxHeight: '90vh', overflowY: 'auto' }}>
            <h3>{editingPlanId ? 'Edit' : 'Create'} Plan</h3>
            <form onSubmit={handleSavePlan} className={styles.form}>
              <h4 className={styles.featureSectionTitle} style={{marginTop: '0'}}>Basic Details</h4>
              <div className={styles.featuresGrid}>
                <div className={styles.formGroup}>
                  <label>Plan Name</label>
                  <input 
                    type="text" 
                    value={planFormData.name}
                    onChange={(e) => setPlanFormData({...planFormData, name: e.target.value})}
                    required
                  />
                </div>
                <div className={styles.formGroup}>
                  <label>Price (₹)</label>
                  <input 
                    type="number" 
                    value={planFormData.price}
                    onChange={(e) => setPlanFormData({...planFormData, price: e.target.value})}
                    required
                  />
                </div>
                <div className={styles.formGroup}>
                  <label>Validity Days</label>
                  <input 
                    type="number" 
                    value={planFormData.validity_days}
                    onChange={(e) => setPlanFormData({...planFormData, validity_days: e.target.value})}
                    required
                    min="1"
                  />
                </div>
                <div className={styles.formGroup} style={{ gridColumn: 'span 2' }}>
                  <label>WhatsApp Campaign Limit</label>
                  <input 
                    type="number" 
                    value={planFormData.whatsapp_campaign_limit}
                    onChange={(e) => setPlanFormData({...planFormData, whatsapp_campaign_limit: e.target.value})}
                    required
                  />
                </div>
              </div>

              <h4 className={styles.featureSectionTitle}>Targeting & Insights Features</h4>
              <div className={styles.featuresGrid}>
                <label className={styles.checkboxLabel}>
                  <input 
                    type="checkbox" 
                    checked={planFormData.has_customer_segmentation}
                    onChange={(e) => setPlanFormData({...planFormData, has_customer_segmentation: e.target.checked})}
                  /> Customer Segmentation
                </label>
                <label className={styles.checkboxLabel}>
                  <input 
                    type="checkbox" 
                    checked={planFormData.has_service_based_targeting}
                    onChange={(e) => setPlanFormData({...planFormData, has_service_based_targeting: e.target.checked})}
                  /> Service Based Targeting
                </label>
                <label className={styles.checkboxLabel}>
                  <input 
                    type="checkbox" 
                    checked={planFormData.has_high_value_targeting}
                    onChange={(e) => setPlanFormData({...planFormData, has_high_value_targeting: e.target.checked})}
                  /> High Value Targeting
                </label>
                <label className={styles.checkboxLabel}>
                  <input 
                    type="checkbox" 
                    checked={planFormData.has_advanced_insights}
                    onChange={(e) => setPlanFormData({...planFormData, has_advanced_insights: e.target.checked})}
                  /> Advanced Insights
                </label>
                <label className={styles.checkboxLabel}>
                  <input 
                    type="checkbox" 
                    checked={planFormData.has_priority_visibility}
                    onChange={(e) => setPlanFormData({...planFormData, has_priority_visibility: e.target.checked})}
                  /> Priority Visibility
                </label>
                <label className={styles.checkboxLabel}>
                  <input 
                    type="checkbox" 
                    checked={planFormData.is_active}
                    onChange={(e) => setPlanFormData({...planFormData, is_active: e.target.checked})}
                  /> Is Active
                </label>
              </div>

              <h4 className={styles.featureSectionTitle}>Advanced Recommendations</h4>
              <div className={styles.featuresGrid}>
                <div className={styles.formGroup}>
                  <label>Upsell Recommendations</label>
                  <select 
                    value={planFormData.has_upsell_recommendations} 
                    onChange={(e) => setPlanFormData({...planFormData, has_upsell_recommendations: e.target.value})}
                  >
                    <option value="none">None</option>
                    <option value="basic">Basic</option>
                    <option value="advanced">Advanced</option>
                  </select>
                </div>
                <div className={styles.formGroup}>
                  <label>Cross-Sell Recommendations</label>
                  <select 
                    value={planFormData.has_cross_sell_recommendations} 
                    onChange={(e) => setPlanFormData({...planFormData, has_cross_sell_recommendations: e.target.value})}
                  >
                    <option value="none">None</option>
                    <option value="basic">Basic</option>
                    <option value="advanced">Advanced</option>
                  </select>
                </div>
              </div>

              <div className={styles.formActions}>
                <button type="submit" className={styles.primaryButton}>Save Plan</button>
                <button type="button" onClick={() => setIsPlanModalOpen(false)} className={styles.cancelButton}>Cancel</button>
              </div>
            </form>
          </div>
        </div>
      )}

      <div className={styles.section}>
        <h2>Assign Commission Plans / Overrides</h2>
        <table className={styles.table}>
          <thead>
            <tr>
              <th>Salon Name</th>
              <th>Owner</th>
              <th>Current Plan</th>
              <th>Billing Type</th>
              <th>Expiry</th>
              <th>Action</th>
            </tr>
          </thead>
          <tbody>
            {salons.map(salon => (
              <tr key={salon.id}>
                <td>
                  {salon.name}
                  {salon.commission_opt_in ? (
                    <span style={{fontSize: '11px', background: '#eab308', color: '#fff', padding: '2px 6px', borderRadius: '4px', marginLeft: '8px', fontWeight: 'bold'}}>
                      Opted Commission
                    </span>
                  ) : null}
                </td>
                <td>{salon.owner}</td>
                <td>{salon.current_plan}</td>
                <td>
                  {salon.billing_type === 'commission' 
                    ? `Commission (${salon.commission_percentage}%)` 
                    : salon.billing_type}
                </td>
                <td>{salon.expiry || 'N/A'}</td>
                <td>
                  <button className={styles.button} onClick={() => setAssigningSalon(salon)}>
                    Assign Plan
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {assigningSalon && (
        <div className={styles.modalOverlay}>
          <div className={styles.modalContent}>
            <h3>Assign Plan to {assigningSalon.name}</h3>
            <form onSubmit={handleAssignPlan} className={styles.form}>
              
              <div className={styles.formGroup}>
                <label>Base Plan Template</label>
                <select value={selectedPlanId} onChange={(e) => setSelectedPlanId(e.target.value)}>
                  {plans.map(p => <option key={p.id} value={p.id}>{p.name} - ₹{p.price} ({p.validity_days} Days)</option>)}
                </select>
              </div>

              <div className={styles.formGroup}>
                <label>Billing Type</label>
                <select value={billingType} onChange={(e) => setBillingType(e.target.value)}>
                  <option value="flat">Subscription Based</option>
                  <option value="commission">Commission Based</option>
                </select>
              </div>

              {billingType === 'commission' && (
                <div className={styles.formGroup}>
                  <label>Commission Percentage (%)</label>
                  <input 
                    type="number" 
                    step="0.01"
                    min="0"
                    max="100"
                    value={commissionPercentage}
                    onChange={(e) => setCommissionPercentage(e.target.value)}
                    required
                  />
                </div>
              )}

              <div className={styles.formActions}>
                <button type="submit" className={styles.primaryButton}>Assign Subscription</button>
                <button type="button" onClick={() => setAssigningSalon(null)} className={styles.cancelButton}>Cancel</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
